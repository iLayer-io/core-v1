// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {PermitHelper} from "./libraries/PermitHelper.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {IRouterCallable} from "./interfaces/IRouterCallable.sol";
import {BaseRouter} from "./routers/BaseRouter.sol";
import {Validator} from "./Validator.sol";
import {RouterEnabled} from "./RouterEnabled.sol";

/**
 * @title OrderHub contract
 * @dev Contract that stores user orders and input tokens and sends the fill message
 * @custom:security-contact security@ilayer.io
 */
contract OrderHub is
    IRouterCallable,
    RouterEnabled,
    Validator,
    ReentrancyGuard,
    ERC2771Context,
    IERC165,
    IERC721Receiver,
    IERC1155Receiver
{
    mapping(uint32 chainId => bytes32 spoke) public spokes;
    mapping(bytes32 orderId => Status status) public orders;
    mapping(address user => mapping(uint64 nonce => bool used)) public requestNonces;
    uint64 public maxOrderDeadline;
    uint64 public timeBuffer;
    uint64 public nonce;

    event SpokeUpdated(uint32 chainId, bytes32 oldSpokeAddr, bytes32 newSpokeAddr);
    event TimeBufferUpdated(uint64 indexed oldTimeBufferVal, uint64 indexed newTimeBufferVal);
    event MaxOrderDeadlineUpdated(uint64 indexed oldDeadline, uint64 indexed newDeadline);
    event OrderCreated(bytes32 indexed orderId, uint64 nonce, Order order, address indexed caller);
    event OrderWithdrawn(bytes32 indexed orderId, address indexed caller);
    event OrderSettled(bytes32 indexed orderId, Order order);
    event ERC721Received(address operator, address from, uint256 tokenId, bytes data);
    event ERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data);
    event ERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data);

    error RequestNonceReused();
    error RequestExpired();
    error UndefinedSpoke();
    error InvalidOrderInputApprovals();
    error InvalidOrderSignature();
    error InvalidCallRecipient();
    error InvalidDeadline();
    error InvalidSourceChain();
    error InvalidDestinationChain();
    error OrderDeadlinesMismatch();
    error OrderPrimaryFillerExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error OrderExpired();

    constructor(
        address _owner,
        address _router,
        address _trustedForwarder,
        uint64 _maxOrderDeadline,
        uint64 _timeBuffer
    ) RouterEnabled(_owner, _router) ERC2771Context(_trustedForwarder) {
        maxOrderDeadline = _maxOrderDeadline;
        timeBuffer = _timeBuffer;
    }

    function setSpokeAddress(uint32 chainId, bytes32 spoke) external onlyOwner {
        emit SpokeUpdated(chainId, spokes[chainId], spoke);
        spokes[chainId] = spoke;
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
        BaseRouter.Bridge bridgeSelector,
        bytes calldata extra
    ) external payable nonReentrant returns (bytes32, uint64) {
        Order memory order = request.order;
        address user = BytesUtils.bytes32ToAddress(order.user);

        // validate order request
        if (requestNonces[user][request.nonce]) revert RequestNonceReused();
        if (block.timestamp > request.deadline) revert RequestExpired();
        if (!validateOrderRequest(request, signature)) revert InvalidOrderSignature();
        if (request.order.callData.length > 0 && request.order.callRecipient == bytes32(0)) {
            revert InvalidCallRecipient();
        }

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
                if (nativeValue < input.amount) revert InsufficientGasValue();

                // subtract to the gas computation
                nativeValue -= input.amount;
            }

            _transfer(input.tokenType, user, address(this), tokenAddress, input.tokenId, input.amount);
        }

        BaseRouter.Message memory message = BaseRouter.Message({
            bridge: bridgeSelector,
            chainId: order.destinationChainId,
            destination: spokes[order.destinationChainId],
            payload: abi.encode(orderId),
            extra: extra,
            sender: BytesUtils.addressToBytes32(msg.sender)
        });
        router.send{value: nativeValue}(message);

        emit OrderCreated(orderId, orderNonce, order, _msgSender());

        return (orderId, orderNonce);
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

    function onMessageReceived(uint32 srcChainId, bytes memory data) external override onlyRouter {
        (Order memory order, uint64 orderNonce, bytes32 fundingWallet) = abi.decode(data, (Order, uint64, bytes32));
        if (srcChainId != order.destinationChainId) revert InvalidDestinationChain(); // this should never happen

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
        if (order.sourceChainId != block.chainid) revert InvalidSourceChain();
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (spokes[order.destinationChainId] == "") revert UndefinedSpoke();

        uint256 timestamp = block.timestamp;
        if (timestamp >= order.deadline) revert OrderExpired();
        if (timestamp >= order.primaryFillerDeadline) revert OrderPrimaryFillerExpired();
        if (order.deadline > timestamp + maxOrderDeadline) revert InvalidDeadline();
    }

    function _applyPermits(bytes memory permit, address user, address token) internal {
        (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permit, (uint256, uint256, uint8, bytes32, bytes32));

        PermitHelper.trustlessPermit(token, user, address(this), value, deadline, v, r, s);
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
