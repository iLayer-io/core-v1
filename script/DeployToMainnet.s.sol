// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CREATE3Factory} from "create3-factory/src/CREATE3Factory.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";

contract DeployToMainnetScript is Script {
    bytes32 salt = keccak256(abi.encodePacked(vm.envString("SALT")));
    bytes32 hubSalt = keccak256(abi.encodePacked("hub-", vm.envString("SALT")));
    bytes32 spokeSalt = keccak256(abi.encodePacked("spoke-", vm.envString("SALT")));

    address owner = vm.envAddress("OWNER");
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
    address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER");
    address router = vm.envAddress("ROUTER");
    uint256 maxDeadline = vm.envUint("MAX_DEADLINE");
    uint256 buffer = vm.envUint("WITHDRAW_TIME_BUFFER");

    uint256 remoteCount = vm.envUint("REMOTE_ENDPOINT_COUNT");

    function run() external {
        vm.startBroadcast(ownerPrivateKey);

        CREATE3Factory factory = new CREATE3Factory{salt: salt}();

        address hubAddr = factory.deploy(
            hubSalt,
            abi.encodePacked(
                type(OrderHub).creationCode,
                abi.encode(owner, router, trustedForwarder, uint64(maxDeadline), uint64(buffer))
            )
        );

        address spokeAddr =
            factory.deploy(spokeSalt, abi.encodePacked(type(OrderSpoke).creationCode, abi.encode(owner, router)));

        console2.log("hub: ", hubAddr);
        console2.log("spoke: ", spokeAddr);

        /*
        @todo fix it
        for (uint256 i = 0; i < remoteCount; i++) {
            uint256 remoteEndpoint;

            if (i == 0) {
                remoteEndpoint = vm.envUint("REMOTE_ENDPOINT_0");
            } else if (i == 1) {
                remoteEndpoint = vm.envUint("REMOTE_ENDPOINT_1");
            } // Add more to deploy on more networks

            hub.setPeer(uint32(remoteEndpoint), addressToBytes32(spokeAddr));
            spoke.setPeer(uint32(remoteEndpoint), addressToBytes32(hubAddr));
        }
        */

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
