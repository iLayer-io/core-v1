// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract DeployToMainnetScript is Script {
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");

    function run() external {
        vm.startBroadcast(userPrivateKey);

        OrderHub hub = new OrderHub();

        vm.stopBroadcast();
    }
}
