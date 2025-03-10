// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Create3Factory} from "../lib/create3-factory/src/CREATE3Factory.sol";

contract DeployCreate3Factory is Script {
    function run() external {
        // Recupera la chiave privata dal file d'ambiente
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Avvia il broadcast per il deploy
        vm.startBroadcast(deployerPrivateKey);
        Create3Factory factory = new Create3Factory();
        vm.stopBroadcast();

        console.log("Deployed Create3Factory at:", address(factory));
    }
}
