// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Root} from "./Root.sol";
import {Executor} from "./Executor.sol";

/**
 * @title OrderSpoke contract
 * @dev Contract that manages order fill and output token transfer from the solver to the user
 * @custom:security-contact security@ilayer.io
 */
contract OrderSpoke is Root, ReentrancyGuard, OApp {
    using SafeERC20 for IERC20;

    enum OrderStatus {
        NULL,
        PENDING,
        FILLED
    }

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;
    uint256 public constant FEE_RESOLUTION = 10_000;

    Executor public immutable executor;
    mapping(bytes32 => OrderStatus) public orders;
    uint256 public fee;

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event PendingOrderReceived(bytes32 indexed orderId, uint32 indexed spokeEid);
    event OrderFilled(bytes32 indexed orderId, Order indexed order, address indexed caller, MessagingReceipt receipt);
    event TokenSweep(
        Type indexed tokenType, uint256 tokenId, address indexed token, address indexed to, uint256 amount
    );

    error InvalidFeeValue();
    error OrderAlreadyFilled();
    error OrderExpired();
    error InvalidDestinationChain();
    error RestrictedToPrimaryFiller();
    error ExternalCallFailed();

    constructor(address _router) Ownable(msg.sender) OApp(_router, msg.sender) {
        executor = new Executor();
    }

    function setFee(uint256 newFee) external onlyOwner {
        if (newFee > FEE_RESOLUTION) revert InvalidFeeValue();

        emit FeeUpdated(fee, newFee);
        fee = newFee;
    }

    function sweep(Type tokenType, uint256 tokenId, address token, address to, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        _transfer(tokenType, address(this), to, token, tokenId, amount);

        emit TokenSweep(tokenType, tokenId, token, to, amount);
    }

    function estimateBridgingFee(uint32 dstEid, bytes memory payload, bytes calldata options)
        public
        view
        returns (uint256)
    {
        MessagingFee memory _fee = _quote(dstEid, payload, options, false);
        return _fee.nativeFee;
    }

    function fillOrder(
        Order memory order,
        uint64 orderNonce,
        bytes32 fundingWallet,
        uint256 maxGas,
        bytes calldata options
    ) external payable nonReentrant returns (MessagingReceipt memory) {
        if (msg.value <= order.callValue) revert InsufficientGasValue();

        bytes32 orderId = getOrderId(order, orderNonce);
        _validateOrder(order, orderId);
        orders[orderId] = OrderStatus.FILLED;

        uint256 value = _transferFunds(order);
        if (order.callData.length > 0) {
            if (value < order.callValue) revert InsufficientGasValue();
            value -= order.callValue;
            _callHook(order, maxGas);
        }

        bytes memory payload = abi.encode(order, orderNonce, fundingWallet);
        MessagingReceipt memory receipt =
            _lzSend(order.sourceChainEid, payload, options, MessagingFee(value, 0), payable(msg.sender));

        emit OrderFilled(orderId, order, msg.sender, receipt);

        return receipt;
    }

    function _validateOrder(Order memory order, bytes32 orderId) internal view {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > order.deadline) revert OrderExpired();
        if (orders[orderId] != OrderStatus.PENDING) revert OrderAlreadyFilled();
        if (order.destinationChainEid != endpoint.eid()) revert InvalidDestinationChain();

        address filler = BytesUtils.bytes32ToAddress(order.filler);
        if (filler != address(0) && currentTime <= order.primaryFillerDeadline && filler != msg.sender) {
            revert RestrictedToPrimaryFiller();
        }
    }

    function _callHook(Order memory order, uint256 maxGas) internal {
        address callRecipient = BytesUtils.bytes32ToAddress(order.callRecipient);
        bool successful = executor.exec{value: order.callValue}(
            callRecipient, maxGas, order.callValue, MAX_RETURNDATA_COPY_SIZE, order.callData
        );
        if (!successful) revert ExternalCallFailed();
    }

    function _transferFunds(Order memory order) internal returns (uint256) {
        uint256 nativeValue = msg.value;

        address to = BytesUtils.bytes32ToAddress(order.user);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];
            uint256 amount = output.amount;
            uint256 feeAmount = 0;
            address tokenAddress;

            if (output.tokenType == Type.NATIVE || output.tokenType == Type.ERC20) {
                feeAmount = amount * fee / FEE_RESOLUTION;
                amount -= feeAmount;
            }

            if (output.tokenType == Type.NATIVE) {
                // check that enough value was supplied
                if (msg.value <= output.amount) revert InsufficientGasValue();

                // subtract to the gas computation
                nativeValue -= output.amount;
            } else {
                tokenAddress = BytesUtils.bytes32ToAddress(output.tokenAddress);
            }

            // main transfer
            _transfer(output.tokenType, msg.sender, to, tokenAddress, output.tokenId, amount);

            // fee transfer
            if (feeAmount > 0) {
                _transfer(output.tokenType, msg.sender, address(this), tokenAddress, output.tokenId, feeAmount);
            }
        }

        return nativeValue;
    }

    function _lzReceive(Origin calldata data, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
    {
        (bytes32 orderId) = abi.decode(payload, (bytes32));
        orders[orderId] = OrderStatus.PENDING;

        emit PendingOrderReceived(orderId, data.srcEid);
    }

    function _payNative(uint256 _nativeFee) internal pure override returns (uint256 nativeFee) {
        return _nativeFee;
    }
}
