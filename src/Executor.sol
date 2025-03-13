// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ExcessivelySafeCall} from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";

/**
 * @title Executor contract
 * @dev Helper to execute arbitrary contract calls
 * @custom:security-contact security@ilayer.io
 */
contract Executor {
    using ExcessivelySafeCall for address;

    address public immutable owner;

    event ContractCallExecuted(address indexed target, uint256 value, bytes data);

    error RestrictedToOwner();

    constructor() {
        owner = msg.sender;
    }

    function exec(address target, uint256 gas, uint256 value, uint16 maxCopy, bytes memory data)
        external
        payable
        returns (bool)
    {
        if (owner != msg.sender) revert RestrictedToOwner();

        (bool res,) = target.excessivelySafeCall(gas, value, maxCopy, data);

        emit ContractCallExecuted(target, value, data);

        return res;
    }
}
