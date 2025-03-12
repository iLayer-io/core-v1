// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Root} from "../src/Root.sol";
import {OrderHubMock} from "./mocks/OrderHubMock.sol";
import {OrderSpokeMock} from "./mocks/OrderSpokeMock.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract BaseScript is Script {
    OrderHubMock public hub;
    OrderSpokeMock public spoke;
    MockERC20 public inputToken;
    MockERC20 public outputToken;

    address user = vm.envAddress("USER_ADDRESS");
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    address filler = vm.envAddress("FILLER_ADDRESS");
    uint256 fillerPrivateKey = vm.envUint("FILLER_PRIVATE_KEY");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint64 fillerDeadlineOffset = uint64(vm.envUint("FILLER_DEADLINE_OFFSET"));
    uint64 mainDeadlineOffset = uint64(vm.envUint("MAIN_DEADLINE_OFFSET"));

    constructor() {
        fillerDeadlineOffset += uint64(block.timestamp);
        mainDeadlineOffset += uint64(block.timestamp);
    }

    function deployContracts() public {
        hub = new OrderHubMock(1 days, 0);
        spoke = new OrderSpokeMock(address(hub));
        vm.setEnv("HUB_ADDRESS", Strings.toChecksumHexString(address(hub)));
        vm.setEnv("SPOKE_ADDRESS", Strings.toChecksumHexString(address(spoke)));
        console2.log("hub", address(hub));
        console2.log("spoke", address(spoke));

        inputToken = new MockERC20("input", "INPUT");
        outputToken = new MockERC20("output", "OUTPUT");
        vm.setEnv("INPUT_TOKEN_ADDRESS", Strings.toChecksumHexString(address(inputToken)));
        vm.setEnv("OUTPUT_TOKEN_ADDRESS", Strings.toChecksumHexString(address(outputToken)));
        console2.log("inputToken", address(inputToken));
        console2.log("outputToken", address(outputToken));
    }

    function setupContracts() public {
        hub = OrderHubMock(vm.envAddress("HUB_ADDRESS"));
        spoke = OrderSpokeMock(vm.envAddress("SPOKE_ADDRESS"));
        inputToken = MockERC20(vm.envAddress("INPUT_TOKEN_ADDRESS"));
        outputToken = MockERC20(vm.envAddress("OUTPUT_TOKEN_ADDRESS"));
    }

    function buildOrder() public view returns (Root.Order memory) {
        Root.Token[] memory inputs = new Root.Token[](1);
        inputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(address(inputToken)),
            tokenId: 0,
            amount: inputAmount
        });

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(address(outputToken)),
            tokenId: 0,
            amount: outputAmount
        });

        return Root.Order({
            user: BytesUtils.addressToBytes32(user),
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: 1,
            destinationChainEid: 2,
            sponsored: false,
            primaryFillerDeadline: fillerDeadlineOffset,
            deadline: mainDeadlineOffset,
            callRecipient: "",
            callData: "",
            callValue: 0
        });
    }

    function buildSignature(Root.Order memory order) public view returns (bytes memory) {
        bytes32 structHash = hub.hashOrder(order);
        bytes32 domainSeparator = hub.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
