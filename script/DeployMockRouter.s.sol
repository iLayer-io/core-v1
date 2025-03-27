// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockRouter} from "../test/mocks/MockRouter.sol";

contract DeployScript is Script {
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");

    function run() external {
        vm.startBroadcast(ownerPrivateKey);

        MockRouter router = new MockRouter();
        console2.log("MockRouter address: ", address(router));

        vm.stopBroadcast();
    }
}
