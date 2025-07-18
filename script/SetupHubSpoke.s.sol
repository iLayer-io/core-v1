// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {LzRouter} from "../src/routers/LzRouter.sol";

contract SetupHubSpokeScript is Script {
    address owner = vm.envAddress("OWNER");
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
    address hubAddr = vm.envAddress("HUB");
    address spokeAddr = vm.envAddress("SPOKE");
    uint32 chainId = uint32(vm.envUint("CHAIN_ID"));

    function run() external {
        vm.startBroadcast(ownerPrivateKey);
        OrderHub hub = OrderHub(hubAddr);
        OrderSpoke spoke = OrderSpoke(spokeAddr);

        hub.setSpokeAddress(chainId, addressToBytes32(spokeAddr));
        spoke.setHubAddress(chainId, addressToBytes32(hubAddr));
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
