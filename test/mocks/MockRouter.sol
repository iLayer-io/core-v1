// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {
    ILayerZeroEndpointV2,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OApp, MessagingFee, MessagingReceipt, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";

interface ILayerZeroReceiver {
    function lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _message, bytes calldata _extraData)
        external
        payable;
}

contract MockRouter {
    address public delegate;

    function send(MessagingParams calldata _params, address) external payable returns (MessagingReceipt memory) {
        bytes32 guid = bytes32(block.number);
        Origin memory origin = Origin({srcEid: 0, sender: bytes32(0), nonce: 0});
        try ILayerZeroReceiver(BytesUtils.bytes32ToAddress(_params.receiver)).lzReceive{value: msg.value}(
            origin, guid, _params.message, ""
        ) {} catch (bytes memory reason) {
            revert(string(reason));
        }

        return MessagingReceipt({
            guid: guid,
            nonce: uint64(block.timestamp),
            fee: MessagingFee({nativeFee: 0, lzTokenFee: 0})
        });
    }

    function lzToken() external view returns (address) {}

    function setDelegate(address _delegate) external {
        delegate = _delegate;
    }

    function getDelegate(address _address) external view returns (address) {
        return delegate;
    }

    function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory) {}
}
