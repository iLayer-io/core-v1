// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IRouter} from "./interfaces/IRouter.sol";

contract RouterEnabled is Ownable {
    IRouter public router;

    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    error RestrictedToRouter();

    constructor(address _owner, address _router) Ownable(_owner) {
        router = IRouter(_router);
    }

    modifier onlyRouter() {
        if (msg.sender != address(router)) revert RestrictedToRouter();
        _;
    }

    function setRouter(address newRouter) external onlyOwner {
        emit RouterUpdated(address(router), newRouter);
        router = IRouter(newRouter);
    }
}
