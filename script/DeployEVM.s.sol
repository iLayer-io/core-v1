// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {CREATE3Factory} from "create3-factory/src/CREATE3Factory.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {LzRouter} from "../src/routers/LzRouter.sol";

contract DeployEVMScript is Script {
    bytes32 salt = keccak256(abi.encodePacked(vm.envString("SALT")));
    bytes32 hubSalt = keccak256(abi.encodePacked("hub-", vm.envString("SALT")));
    bytes32 spokeSalt = keccak256(abi.encodePacked("spoke-", vm.envString("SALT")));
    bytes32 routerSalt = keccak256(abi.encodePacked("router-", vm.envString("SALT")));

    address owner = vm.envAddress("OWNER");
    uint256 ownerPrivateKey = vm.envUint("OWNER_PRIVATE_KEY");
    address create3Factory = vm.envAddress("CREATE3_FACTORY");
    address trustedForwarder = vm.envAddress("TRUSTED_FORWARDER");
    uint256 maxDeadline = vm.envUint("MAX_DEADLINE");
    uint256 buffer = vm.envUint("WITHDRAW_TIME_BUFFER");
    address axGateway = vm.envAddress("AX_GATEWAY");
    address axGasService = vm.envAddress("AX_GAS_SERVICE");
    address lzRouter = vm.envAddress("LZ_ROUTER");

    function run() external {
        vm.startBroadcast(ownerPrivateKey);

        CREATE3Factory factory;
        if (create3Factory == address(0)) {
            console2.log("Deploying create3 factory...");
            factory = new CREATE3Factory{salt: salt}();
            console2.log("Create3 factory deployed: ", address(factory));
        } else {
            console2.log("Reusing existing create3 factory");
            factory = CREATE3Factory(create3Factory);
        }

        console2.log("Deploying LzRouter...");
        address routerAddr =
            factory.deploy(routerSalt, abi.encodePacked(type(LzRouter).creationCode, abi.encode(owner, lzRouter)));
        console2.log("Router deployed: ", routerAddr);

        console2.log("Deploying OrderHub...");
        address hubAddr = factory.deploy(
            hubSalt,
            abi.encodePacked(
                type(OrderHub).creationCode,
                abi.encode(owner, routerAddr, trustedForwarder, uint64(maxDeadline), uint64(buffer))
            )
        );
        console2.log("Hub deployed: ", hubAddr);

        console2.log("Deploying OrderSpoke...");
        address spokeAddr =
            factory.deploy(spokeSalt, abi.encodePacked(type(OrderSpoke).creationCode, abi.encode(owner, routerAddr)));
        console2.log("Spoke deployed: ", spokeAddr);

        console2.log("Setup same chain hub-spoke connection...");
        
        OrderHub hub = OrderHub(hubAddr);
        OrderSpoke spoke = OrderSpoke(spokeAddr);

        hub.setSpokeAddress(uint32(block.chainid), addressToBytes32(spokeAddr));
        spoke.setHubAddress(uint32(block.chainid), addressToBytes32(hubAddr));

        hub.setSpokeAddress(uint32(42161), addressToBytes32(spokeAddr));
        spoke.setHubAddress(uint32(42161), addressToBytes32(hubAddr));
        console2.log("Completed");

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
