// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IRouterCallable} from "../interfaces/IRouterCallable.sol";
import {BytesUtils} from "../libraries/BytesUtils.sol";

/**
 * @title Base router contract
 * @dev Starting point for all router contracts
 * @custom:security-contact security@ilayer.io
 */
abstract contract BaseRouter is Ownable {
    enum Bridge {
        NULL,
        LAYERZERO,
        AXELAR,
        CCIP,
        ACROSS,
        EVERCLEAR,
        WORMHOLE
    }

    struct Message {
        Bridge bridge;
        uint32 chainId;
        bytes32 destination;
        bytes payload;
        bytes extra;
        bytes32 sender;
    }

    mapping(address caller => bool status) public whitelisted;

    event WhitelistUpdated(address indexed target, bool previousStatus, bool newStatus);
    event MessageBroadcasted(Message message);

    error UnsupportedBridgingRoute();
    error NotWhitelisted();

    constructor(address _owner) Ownable(_owner) {}

    modifier onlyWhitelisted(address caller) {
        if (!whitelisted[caller]) revert NotWhitelisted();
        _;
    }

    function setWhitelisted(address target, bool status) external onlyOwner {
        emit WhitelistUpdated(target, whitelisted[target], status);
        whitelisted[target] = status;
    }

    function send(Message calldata message) external payable virtual;

    function _relay(Message calldata message) internal {
        address dest = BytesUtils.bytes32ToAddress(message.destination);
        IRouterCallable(dest).onMessageReceived(message.chainId, message.payload);
        emit MessageBroadcasted(message);
    }
}
