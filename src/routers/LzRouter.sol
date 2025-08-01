// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OApp, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IRouterCallable} from "../interfaces/IRouterCallable.sol";
import {BytesUtils} from "../libraries/BytesUtils.sol";
import {BaseRouter} from "./BaseRouter.sol";

/**
 * @title Router contract for LayzerZero
 * @dev Helper to execute cross-chain contract calls
 * @custom:security-contact security@ilayer.io
 */
contract LzRouter is BaseRouter, OApp {
    constructor(address _owner, address _router) BaseRouter(_owner) OApp(_router, _owner) {}

    mapping(uint32 chainId => uint32 lzEid) public chainIdToLzChainEid;
    mapping(uint32 lzEid => uint32 chainId) public lzChainEidToChainId;

    event LzEidUpdated(uint32 indexed chainId, uint32 indexed lzEid);
    event MessageRoutedLz(MessagingReceipt msg);

    error UnsupportedLzChain();

    function setLzEid(uint32 chainId, uint32 lzEid) external onlyOwner {
        chainIdToLzChainEid[chainId] = lzEid;
        lzChainEidToChainId[lzEid] = chainId;

        emit LzEidUpdated(chainId, lzEid);
    }

    function send(Message calldata message) external payable virtual override onlyWhitelisted(msg.sender) {
        Bridge selectedBridge = Bridge(message.bridge);
        if (selectedBridge == Bridge.LAYERZERO) {
            uint32 destEid = chainIdToLzChainEid[message.chainId];
            if (destEid == 0) revert UnsupportedLzChain();

            bytes memory payload = abi.encode(message.destination, message.payload);
            address refund = BytesUtils.bytes32ToAddress(message.sender);
            MessagingReceipt memory receipt =
                _lzSend(destEid, payload, message.extra, MessagingFee(msg.value, 0), payable(refund));

            emit MessageRoutedLz(receipt);
        } else if (selectedBridge == Bridge.NULL) {
            BaseRouter._relay(message);
        } else {
            revert UnsupportedBridgingRoute();
        }
    }

    function estimateLzBridgingFee(uint32 dstEid, bytes memory payload, bytes calldata options)
        external
        view
        returns (uint256)
    {
        MessagingFee memory fee = _quote(dstEid, payload, options, false);
        return fee.nativeFee;
    }

    function _lzReceive(Origin calldata origin, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
    {
        (address dest, bytes memory data) = abi.decode(payload, (address, bytes));
        uint32 srcChainId = lzChainEidToChainId[origin.srcEid];
        IRouterCallable(dest).onMessageReceived(srcChainId, data);
    }

    function _payNative(uint256 _nativeFee) internal pure override returns (uint256 nativeFee) {
        return _nativeFee;
    }
}
