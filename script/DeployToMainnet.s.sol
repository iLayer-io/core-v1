// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CREATE3Factory} from "create3-factory/src/CREATE3Factory.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";

contract DeployToMainnetScript is Script {
    bytes32 salt = keccak256("ilayerfhgfjh");

    address owner = vm.envAddress("OWNER");
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
    address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER");
    address router = vm.envAddress("ROUTER");
    uint256 maxDeadline = vm.envUint("MAX_DEADLINE");
    uint256 buffer = vm.envUint("WITHDRAW_TIME_BUFFER");
    uint256 endpointId = vm.envUint("ENDPOINT_ID");

    function run() external {
        vm.startBroadcast(ownerPrivateKey);

        uint32 eId = uint32(endpointId);
        uint64 withdrawTimeBuffer = uint64(buffer);
        uint64 maxOrderDeadline = uint64(maxDeadline);

        CREATE3Factory factory = new CREATE3Factory();

        address hubAddr = factory.deploy(
          salt,
          abi.encodePacked(
              type(OrderHub).creationCode,
              abi.encode(owner, router, trustedForwarder, maxOrderDeadline, withdrawTimeBuffer)
          )
        );
        
        address spokeAddr = factory.deploy(
          salt,
          abi.encodePacked(
              type(OrderSpoke).creationCode,
              abi.encode(owner, router)
          )
        );

        OrderHub hub = OrderHub(hubAddr);
        OrderSpoke spoke = OrderSpoke(spokeAddr);
        hub.setPeer(
          eId,
          addressToBytes32(spokeAddr)
        );
        spoke.setPeer(
          eId,
          addressToBytes32(hubAddr)
        );

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
