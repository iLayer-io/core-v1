// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IRouter {
    enum Bridge {
        NULL,
        LAYERZERO,
        AXELAR,
        CCIP,
        ACROSS
    }

    struct Message {
        Bridge bridge;
        uint32 chainId;
        bytes32 destination;
        bytes payload;
        bytes extra;
    }

    event MessageBroadcasted(Message message);

    error UnsupportedBridgingRoute();

    function send(Message calldata message) external payable;
}
