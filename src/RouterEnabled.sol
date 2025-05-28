// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {BaseRouter} from "./routers/BaseRouter.sol";

contract RouterEnabled is Ownable {
    BaseRouter public router;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    error RestrictedToRouter();

    constructor(address _owner, address _router) Ownable(_owner) {
        router = BaseRouter(_router);
    }

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert RestrictedToRouter();
        _;
    }

    function setRouter(address newRouter) external onlyOwner {
        emit RouterUpdated(address(router), newRouter);
        router = BaseRouter(newRouter);
    }
}
