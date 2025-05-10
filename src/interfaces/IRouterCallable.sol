// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IRouterCallable {
    function onMessageReceived(uint32 srcChainId, bytes memory data) external;
}
