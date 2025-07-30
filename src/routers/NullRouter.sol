// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BaseRouter} from "./BaseRouter.sol";

/**
 * @title Null router contract
 * @dev Helper to execute same-chain contract calls
 * @custom:security-contact security@ilayer.io
 */
contract NullRouter is BaseRouter {
    constructor(address _owner) BaseRouter(_owner) {}

    function send(Message calldata message) external payable override onlyWhitelisted(msg.sender) {
        if (message.bridge == Bridge.NULL) {
            BaseRouter._relay(message);
        } else {
            revert UnsupportedBridgingRoute();
        }
    }
}
