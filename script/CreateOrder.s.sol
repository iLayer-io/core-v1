// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract CreateOrderScript is BaseScript {
    function run() external broadcastTx(userPrivateKey) {
        Validator.Order memory order = buildOrder();

        bytes[] memory permits = new bytes[](1);
        bytes memory signature = buildSignature(order);

        MockERC20 token = MockERC20(fromToken);
        token.approve(address(orderbook), inputAmount);
        token.mint(user, inputAmount);

        (bytes32 id, uint256 nonce) = Orderbook(orderbook).createOrder(order, permits, signature, 0);
        console2.log("order id", string(abi.encodePacked(id)));
        console2.log("order nonce", nonce);
    }
}
