// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract FillOrderScript is BaseScript {
    function run() external {
        vm.startBroadcast(fillerPrivateKey);

        setupContracts();

        uint64 nonce = 1;
        Root.Order memory order = buildOrder();

        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        spoke.fillOrder{value: 1e8}(order, nonce, fillerEncoded, 0, 0, "");
        vm.stopBroadcast();
    }
}
