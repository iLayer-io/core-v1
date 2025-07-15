// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CREATE3Factory} from "create3-factory/src/CREATE3Factory.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {LzRouter} from "../src/routers/LzRouter.sol";
import {AxLzRouter} from "../src/routers/AxLzRouter.sol";

contract SetupLayerZeroEVMScript is Script {
    address owner = vm.envAddress("OWNER");
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
    address routerAddr = vm.envAddress("ROUTER");
    address peerRouter = vm.envAddress("PEER_ROUTER");
    uint32 chainId = uint32(vm.envUint("CHAIN_ID"));
    uint32 lzEid = uint32(vm.envUint("LZ_EID"));
    bool isMixedRouter = vm.envExists("IS_MIXED_ROUTER");
    address hub = vm.envAddress("HUB");
    address spoke = vm.envAddress("SPOKE");

    function run() external {
        vm.startBroadcast(ownerPrivateKey);

        if (isMixedRouter) {
            console2.log("Setup of AxLzRouter in progress...");
            AxLzRouter router = AxLzRouter(routerAddr);
            router.setLzEid(chainId, lzEid);
            router.setPeer(lzEid, addressToBytes32(peerRouter));
            router.setWhitelisted(hub, true);
            router.setWhitelisted(spoke, true);
        } else {
            console2.log("Setup of LzRouter in progress...");
            LzRouter router = LzRouter(routerAddr);
            router.setLzEid(chainId, lzEid);
            router.setPeer(lzEid, addressToBytes32(peerRouter));
            router.setWhitelisted(hub, true);
            router.setWhitelisted(spoke, true);
        }
        console2.log("Setup completed");

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
