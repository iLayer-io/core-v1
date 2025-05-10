// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IRouterCallable} from "../../src/interfaces/IRouterCallable.sol";
import {RouterEnabled} from "../../src/RouterEnabled.sol";

contract TargetContract is RouterEnabled, IRouterCallable {
    uint256 public bar = 0;

    constructor(address _owner, address _router) RouterEnabled(_owner, _router) {}

    function foo(uint256 val) external payable {
        bar = val;
    }

    function onMessageReceived(uint32, bytes memory data) external override {
        bar = abi.decode(data, (uint256));
    }
}
