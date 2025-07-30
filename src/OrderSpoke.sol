// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {IRouterCallable} from "./interfaces/IRouterCallable.sol";
import {BaseRouter} from "./routers/BaseRouter.sol";
import {Root} from "./Root.sol";
import {Executor} from "./Executor.sol";
import {RouterEnabled} from "./RouterEnabled.sol";

/**
 * @title OrderSpoke contract
 * @dev Contract that manages order fill and output token transfer from the solver to the user
 * @custom:security-contact security@ilayer.io
 */
contract OrderSpoke is IRouterCallable, RouterEnabled, Root, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;
    uint256 public constant FEE_RESOLUTION = 10_000;
    Executor public immutable executor;

    mapping(uint32 chainId => bytes32 hub) public hubs;
    mapping(bytes32 => Status) public orders;
    uint256 public fee;

    event HubUpdated(uint32 chainId, bytes32 oldHubAddr, bytes32 newHubAddr);
    event FeeUpdated(uint256 indexed oldFee, uint256 indexed newFee);
    event PendingOrderReceived(bytes32 indexed orderId, uint32 indexed spokeChainId);
    event OrderFilled(bytes32 indexed orderId, Order order, address indexed caller);
    event TokenSweep(
        Type indexed tokenType, uint256 tokenId, address indexed token, address indexed to, uint256 amount
    );

    error UndefinedHub();
    error InvalidFundingWallet();
    error InvalidFeeValue();
    error InvalidOrder();
    error OrderAlreadyFilled();
    error OrderExpired();
    error InvalidDestinationChain();
    error RestrictedToPrimaryFiller();
    error ExternalCallFailed();

    constructor(address _owner, address _router) RouterEnabled(_owner, _router) {
        executor = new Executor();
    }

    function setHubAddress(uint32 chainId, bytes32 hub) external onlyOwner {
        emit HubUpdated(chainId, hubs[chainId], hub);
        hubs[chainId] = hub;
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

    function fillOrder(
        Order memory order,
        uint64 orderNonce,
        bytes32 fundingWallet,
        uint256 maxGas,
        BaseRouter.Bridge bridgeSelector,
        bytes calldata extra
    ) external payable nonReentrant {
        if (msg.value < order.callValue) revert InsufficientGasValue();
        if (fundingWallet == hubs[order.sourceChainId] || fundingWallet == bytes32(0)) revert InvalidFundingWallet();

        bytes32 orderId = getOrderId(order, orderNonce);
        _validateOrder(order, orderId);
        orders[orderId] = Status.FILLED;

        uint256 nativeValue = _transferFunds(order);
        if (order.callData.length > 0) {
            if (nativeValue < order.callValue) revert InsufficientGasValue();
            nativeValue -= order.callValue;
            _callHook(order, maxGas);
        }

        BaseRouter.Message memory message = BaseRouter.Message({
            bridge: bridgeSelector,
            chainId: order.sourceChainId,
            destination: hubs[order.sourceChainId],
            payload: abi.encode(order, orderNonce, fundingWallet),
            extra: extra,
            sender: BytesUtils.addressToBytes32(msg.sender)
        });
        router.send{value: nativeValue}(message);

        emit OrderFilled(orderId, order, msg.sender);
    }

    function _validateOrder(Order memory order, bytes32 orderId) internal view {
        uint64 currentTime = uint64(block.timestamp);
        if (hubs[order.sourceChainId] == "") revert UndefinedHub(); // avoids filling an order we cannot dispatch
        if (currentTime > order.deadline) revert OrderExpired();
        if (orders[orderId] == Status.NULL) revert InvalidOrder();
        if (orders[orderId] == Status.FILLED) revert OrderAlreadyFilled();
        if (order.destinationChainId != block.chainid) revert InvalidDestinationChain();

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

        address to = BytesUtils.bytes32ToAddress(order.recipient);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];
            uint256 amount = output.amount;
            uint256 feeAmount = 0;
            address tokenAddress;

            if (output.tokenType == Type.NATIVE || output.tokenType == Type.FUNGIBLE_TOKEN) {
                feeAmount = amount * fee / FEE_RESOLUTION;
                amount -= feeAmount;
            }

            if (output.tokenType == Type.NATIVE) {
                // check that enough value was supplied
                if (nativeValue <= output.amount) revert InsufficientGasValue();

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

    function onMessageReceived(uint32 srcChainId, bytes memory data) external override onlyRouter {
        if (hubs[srcChainId] == "") revert UndefinedHub(); // avoids saving an order we cannot fill

        (bytes32 orderId) = abi.decode(data, (bytes32));
        orders[orderId] = Status.PENDING;

        emit PendingOrderReceived(orderId, srcChainId);
    }
}
