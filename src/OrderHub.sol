// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {OApp, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {PermitHelper} from "./libraries/PermitHelper.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Validator} from "./Validator.sol";

/**
 * @title OrderHub contract
 * @dev Contract that stores user orders and input tokens and sends the fill message
 * @custom:security-contact security@ilayer.io
 */
contract OrderHub is Validator, ReentrancyGuard, OApp, ERC2771Context, IERC165, IERC721Receiver, IERC1155Receiver {
    mapping(bytes32 orderId => Status status) public orders;
    mapping(address user => mapping(uint64 nonce => bool used)) public requestNonces;
    uint64 public maxOrderDeadline;
    uint64 public timeBuffer;
    uint64 public nonce;

    event TimeBufferUpdated(uint64 oldTimeBufferVal, uint64 newTimeBufferVal);
    event MaxOrderDeadlineUpdated(uint64 oldDeadline, uint64 newDeadline);
    event OrderCreated(bytes32 indexed orderId, uint64 nonce, Order order, address indexed caller);
    event OrderWithdrawn(bytes32 indexed orderId, address indexed caller);
    event OrderSettled(bytes32 indexed orderId, Order indexed order);
    event ERC721Received(address operator, address from, uint256 tokenId, bytes data);
    event ERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data);
    event ERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data);

    error RequestNonceReused();
    error RequestExpired();
    error InvalidDestinationEndpoint();
    error InvalidOrderInputApprovals();
    error InvalidOrderSignature();
    error InvalidDeadline();
    error InvalidSourceChain();
    error OrderDeadlinesMismatch();
    error OrderPrimaryFillerExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error OrderExpired();

    constructor(address _trustedForwarder, address _router, uint64 _maxOrderDeadline, uint64 _timeBuffer)
        Ownable(msg.sender)
        OApp(_router, msg.sender)
        ERC2771Context(_trustedForwarder)
    {
        maxOrderDeadline = _maxOrderDeadline;
        timeBuffer = _timeBuffer;
    }

    function setTimeBuffer(uint64 newTimeBuffer) external onlyOwner {
        emit TimeBufferUpdated(timeBuffer, newTimeBuffer);
        timeBuffer = newTimeBuffer;
    }

    function setMaxOrderDeadline(uint64 newMaxOrderDeadline) external onlyOwner {
        emit MaxOrderDeadlineUpdated(maxOrderDeadline, newMaxOrderDeadline);
        maxOrderDeadline = newMaxOrderDeadline;
    }

    /// @notice create off-chain order, signature must be valid
    function createOrder(
        OrderRequest memory request,
        bytes[] memory permits,
        bytes memory signature,
        bytes calldata options
    ) external payable nonReentrant returns (bytes32, uint64, MessagingReceipt memory) {
        Order memory order = request.order;
        address user = BytesUtils.bytes32ToAddress(order.user);

        // validate order request
        if (requestNonces[user][request.nonce]) revert RequestNonceReused();
        if (block.timestamp > request.deadline) revert RequestExpired();
        if (!validateOrderRequest(request, signature)) revert InvalidOrderSignature();

        // validate order
        _checkOrderValidity(order, permits);

        requestNonces[user][request.nonce] = true; // mark the nonce as used
        uint64 orderNonce = ++nonce; // increment the nonce to guarantee order uniqueness
        bytes32 orderId = getOrderId(order, orderNonce);
        orders[orderId] = Status.ACTIVE;

        uint256 nativeValue = msg.value;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = BytesUtils.bytes32ToAddress(input.tokenAddress);
            if (permits[i].length > 0) {
                _applyPermits(permits[i], user, tokenAddress);
            }

            if (input.tokenType == Type.NATIVE) {
                // check that enough value was supplied
                if (msg.value <= input.amount) revert InsufficientGasValue();

                // subtract to the gas computation
                nativeValue -= input.amount;
            }

            _transfer(input.tokenType, user, address(this), tokenAddress, input.tokenId, input.amount);
        }

        bytes memory payload = abi.encode(orderId);
        MessagingReceipt memory receipt =
            _lzSend(order.destinationChainEid, payload, options, MessagingFee(nativeValue, 0), payable(_msgSender()));

        emit OrderCreated(orderId, orderNonce, order, _msgSender());

        return (orderId, orderNonce, receipt);
    }

    function withdrawOrder(Order memory order, uint64 orderNonce) external nonReentrant {
        address user = BytesUtils.bytes32ToAddress(order.user);
        bytes32 orderId = getOrderId(order, orderNonce);
        if (user != _msgSender() || order.deadline + timeBuffer > block.timestamp || orders[orderId] != Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }

        orders[orderId] = Status.WITHDRAWN;

        // transfer input assets back to the user
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = BytesUtils.bytes32ToAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), user, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderWithdrawn(orderId, user);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        emit ERC721Received(operator, from, tokenId, data);
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        emit ERC1155Received(operator, from, id, value, data);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        emit ERC1155BatchReceived(operator, from, ids, values, data);
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function _lzReceive(Origin calldata data, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
        nonReentrant
    {
        (Order memory order, uint64 orderNonce, bytes32 fundingWallet) = abi.decode(payload, (Order, uint64, bytes32));
        if (data.srcEid != order.destinationChainEid) revert InvalidSourceChain(); // this should never happen

        bytes32 orderId = getOrderId(order, orderNonce);

        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled(); // this should never happen
        orders[orderId] = Status.FILLED;

        address fundingWalletDecoded = BytesUtils.bytes32ToAddress(fundingWallet);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = BytesUtils.bytes32ToAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), fundingWalletDecoded, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderSettled(orderId, order);
    }

    function _checkOrderValidity(Order memory order, bytes[] memory permits) internal view {
        if (peers[order.destinationChainEid] == bytes32(0) || order.sourceChainEid == order.destinationChainEid) {
            revert InvalidDestinationEndpoint();
        }
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (order.deadline > block.timestamp + maxOrderDeadline) revert InvalidDeadline();
        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp >= order.deadline) revert OrderExpired();
        if (block.timestamp >= order.primaryFillerDeadline) revert OrderPrimaryFillerExpired();
        if (order.sourceChainEid != endpoint.eid()) revert InvalidSourceChain();
    }

    function _applyPermits(bytes memory permit, address user, address token) internal {
        (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permit, (uint256, uint256, uint8, bytes32, bytes32));

        PermitHelper.trustlessPermit(token, user, address(this), value, deadline, v, r, s);
    }

    function estimateFee(uint32 dstEid, bytes memory payload, bytes calldata options) public view returns (uint256) {
        MessagingFee memory fee = _quote(dstEid, payload, options, false);
        return fee.nativeFee;
    }

    function _payNative(uint256 _nativeFee) internal pure override returns (uint256 nativeFee) {
        return _nativeFee;
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _contextSuffixLength() internal view override(ERC2771Context, Context) returns (uint256) {
        return ERC2771Context._contextSuffixLength();
    }
}
