// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IRouterCallable} from "../interfaces/IRouterCallable.sol";
import {BytesUtils} from "../libraries/BytesUtils.sol";

/**
 * @title Base router contract
 * @dev Helper to execute same-chain contract calls
 * @custom:security-contact security@ilayer.io
 */
contract NullRouter is IRouter, Ownable {
    constructor(address _owner) Ownable(_owner) {}

    function send(Message calldata message) external payable override(IRouter) {
        if (message.chainId == block.chainid) {
            address dest = BytesUtils.bytes32ToAddress(message.destination);
            IRouterCallable(dest).onMessageReceived(message.chainId, message.payload);
            emit MessageBroadcasted(message);
        } else {
            revert UnsupportedBridgingRoute();
        }
    }
}
