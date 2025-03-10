// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {CREATE3Factory} from "../../lib/create3-factory/src/CREATE3Factory.sol";
import {OrderHub} from "../../src/OrderHub.sol";
import {OrderSpoke} from "../../src/OrderSpoke.sol";

interface ILayerZeroConfig {
    function setSendLibrary(address lib) external;

    function setReceiveLibrary(address lib) external;

    // setConfig: configType 1 for Executor, 2 for ULN/Security
    function setConfig(uint8 configType, bytes calldata config) external;
}

interface IPeerConfig {
    // Sets the peer for cross-chain messaging: remote chain id and remote peer address (as bytes32)
    function setPeer(uint16 _remoteChainId, bytes32 _peer) external;
}

contract DeployHubSpoke is Script {
    // Get the CREATE3Factory address from an environment variable
    string create3FactoryAddrStr = vm.envString("CREATE3_FACTORY");

    // Unique salts for deterministic deployment
    bytes32 constant HUB_SALT = keccak256("OrderHub");
    bytes32 constant SPOKE_SALT = keccak256("OrderSpoke");

    // Get values from environment variables (populated by the shell script)
    string endpointAddress = vm.envString("ENDPOINT_ADDRESS");
    string sendLibraryAddr = vm.envString("SEND_LIBRARY");
    string receiveLibraryAddr = vm.envString("RECEIVE_LIBRARY");

    // ULN configuration parameters
    uint256 ulnConfirmations = vm.envUint("ULN_CONFIRMATIONS");
    uint256 ulnRequiredDVNCount = vm.envUint("ULN_REQUIRED_DVN_COUNT");
    uint256 ulnOptionalDVNCount = vm.envUint("ULN_OPTIONAL_DVN_COUNT");
    uint256 ulnOptionalDVNThreshold = vm.envUint("ULN_OPTIONAL_DVN_THRESHOLD");
    string ulRequiredDVN0 = vm.envString("ULN_REQUIRED_DVN_0");
    string ulRequiredDVN1 = vm.envString("ULN_REQUIRED_DVN_1");

    // Executor configuration parameters
    string executorAddress = vm.envString("EXECUTOR_ADDRESS");
    uint256 executorMaxMessageSize = vm.envUint("EXECUTOR_MAX_MESSAGE_SIZE");

    // Peer configuration: number of remote chain ids and each remote chain id.
    uint256 remoteChainCount = vm.envUint("REMOTE_CHAIN_COUNT");

    // Helper: convert a string ("0x...") to address
    function parseAddr(string memory _a) internal pure returns (address) {
        bytes memory tmp = bytes(_a);
        require(tmp.length == 42, "Invalid address length");
        uint160 iaddr = 0;
        for (uint256 i = 2; i < 42; i++) {
            // Skip "0x"
            uint8 b = uint8(tmp[i]);
            iaddr *= 16;
            if (b >= 48 && b <= 57) {
                iaddr += b - 48;
            } else if (b >= 65 && b <= 70) {
                iaddr += b - 55;
            } else if (b >= 97 && b <= 102) {
                iaddr += b - 87;
            } else {
                revert("Invalid character in address");
            }
        }
        return address(iaddr);
    }

    // Helper to get remote chain id from environment variables by index.
    // The environment variable name should be REMOTE_CHAIN_ID_0, REMOTE_CHAIN_ID_1, etc.
    function getRemoteChainId(uint256 index) internal view returns (uint256) {
        string memory varName = string(
            abi.encodePacked("REMOTE_CHAIN_ID_", uint2str(index))
        );
        return vm.envUint(varName);
    }

    // Helper to convert uint to string
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(j % 10));
            bstr[k] = bytes1(temp);
            j /= 10;
        }
        return string(bstr);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Parse CREATE3_FACTORY address from environment variable
        address create3FactoryAddr = parseAddr(create3FactoryAddrStr);

        // Instantiate the CREATE3 Factory using the provided address
        CREATE3Factory factory = CREATE3Factory(create3FactoryAddr);

        // Deploy OrderHub using CREATE3
        bytes memory hubCreationCode = abi.encodePacked(
            type(OrderHub).creationCode,
            abi.encode(parseAddr(endpointAddress))
        );
        factory.deploy(HUB_SALT, hubCreationCode);
        address hubAddress = factory.getDeployed(deployerAddr, HUB_SALT);

        // Deploy OrderSpoke using CREATE3
        bytes memory spokeCreationCode = abi.encodePacked(
            type(OrderSpoke).creationCode,
            abi.encode(parseAddr(endpointAddress))
        );
        factory.deploy(SPOKE_SALT, spokeCreationCode);
        address spokeAddress = factory.getDeployed(deployerAddr, SPOKE_SALT);

        // Initialize contracts
        OrderHub hub = OrderHub(hubAddress);
        OrderSpoke spoke = OrderSpoke(spokeAddress);

        // Configure libraries
        ILayerZeroConfig(address(hub)).setSendLibrary(
            parseAddr(sendLibraryAddr)
        );
        ILayerZeroConfig(address(spoke)).setReceiveLibrary(
            parseAddr(receiveLibraryAddr)
        );

        // Prepare ULN config encoding
        bytes memory ulnConfig = abi.encode(
            ulnConfirmations,
            ulnRequiredDVNCount,
            ulnOptionalDVNCount,
            ulnOptionalDVNThreshold,
            [parseAddr(ulRequiredDVN0), parseAddr(ulRequiredDVN1)],
            new address[](0)
        );
        // Prepare Executor config encoding
        bytes memory executorConfig = abi.encode(
            parseAddr(executorAddress),
            executorMaxMessageSize
        );

        // Call native setConfig: 1 for Executor, 2 for ULN/Security
        ILayerZeroConfig(address(hub)).setConfig(1, executorConfig);
        ILayerZeroConfig(address(hub)).setConfig(2, ulnConfig);
        ILayerZeroConfig(address(spoke)).setConfig(2, ulnConfig);

        // Set peer configuration for all remote chains (including the local chain, if desired)
        for (uint256 i = 0; i < remoteChainCount; i++) {
            uint256 remoteId = getRemoteChainId(i);
            // For Hub, the remote peer should be the Spoke's address on the remote chain
            IPeerConfig(address(hub)).setPeer(
                uint16(remoteId),
                bytes32(uint256(uint160(spokeAddress)))
            );
            // For Spoke, the remote peer should be the Hub's address on the remote chain
            IPeerConfig(address(spoke)).setPeer(
                uint16(remoteId),
                bytes32(uint256(uint160(hubAddress)))
            );
        }

        vm.stopBroadcast();

        console.log("OrderHub deployed at:", hubAddress);
        console.log("OrderSpoke deployed at:", spokeAddress);
    }
}
