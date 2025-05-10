// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderHelper} from "../src/libraries/OrderHelper.sol";
import {IRouter} from "../src/interfaces/IRouter.sol";

contract CreateOrderScript is Script {
    address router = vm.envAddress("ROUTER");
    uint256 bridge = vm.envUint("BRIDGE");
    uint32 sourceChain = uint32(vm.envUint("SOURCE_CHAIN"));
    uint32 destChain = uint32(vm.envUint("DEST_CHAIN"));
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    address user = vm.envAddress("USER");
    address filler = vm.envAddress("FILLER");
    address fromToken = vm.envAddress("FROM_TOKEN");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    address toToken = vm.envAddress("TO_TOKEN");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint256 primaryFillerDeadlineOffset = vm.envUint("PRIMARY_FILLER_DEADLINE_OFFSET");
    uint256 deadlineOffset = vm.envUint("DEADLINE_OFFSET");
    address hubAddr = vm.envAddress("HUB");

    bytes[] public permits;

    function run() external {
        vm.startBroadcast(userPrivateKey);

        OrderHub.OrderRequest memory orderRequest = OrderHelper.buildOrderRequest(
            sourceChain,
            destChain,
            user,
            filler,
            fromToken,
            inputAmount,
            toToken,
            outputAmount,
            primaryFillerDeadlineOffset,
            deadlineOffset
        );
        OrderHub hub = OrderHub(hubAddr);
        bytes memory signature = buildSignature(hub, orderRequest, userPrivateKey);

        (bytes32 id, uint64 nonce) =
            OrderHelper.createOrder(router, hub, destChain, orderRequest, permits, signature, 0, IRouter.Bridge(bridge));

        console2.log("Order id: ");
        console2.logBytes32(id);
        console2.log("Order nonce: ", nonce);

        vm.stopBroadcast();
    }

    function buildSignature(OrderHub hub, Root.OrderRequest memory request, uint256 user_pk)
        public
        view
        returns (bytes memory)
    {
        bytes32 structHash = hub.hashOrderRequest(request);
        bytes32 domainSeparator = hub.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
