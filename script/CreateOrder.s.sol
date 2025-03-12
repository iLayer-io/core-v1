// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import {Root} from "../src/Root.sol";
import {OrderHubMock} from "./mocks/OrderHubMock.sol";
import {BaseScript} from "./BaseScript.sol";

contract CreateOrderScript is BaseScript {
    function run() external {
        vm.startBroadcast(userPrivateKey);

        setupContracts();

        /*
        Root.Order memory order = buildOrder();

        bytes[] memory permits = new bytes[](1);
        bytes memory signature = buildSignature(order);

        inputToken.approve(address(hub), inputAmount);
        inputToken.mint(user, inputAmount);

        Root.OrderRequest memory request = Root.OrderRequest({
            order: order,
            deadline: uint64(block.timestamp + 1 days),
            nonce: uint64(block.number)
        });
        (bytes32 id, uint64 nonce) = hub.createOrder(request, permits, signature);

        console2.log("order id:");
        console2.logBytes32(id);
        console2.log("order nonce:");
        console2.log(nonce);
        */

        vm.stopBroadcast();
    }
}
