// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderHelper} from "../src/libraries/OrderHelper.sol";
import {MockRouter} from "../test/mocks/MockRouter.sol";

contract CreateOrderScript is Script {
    uint32 sourceEid = uint32(vm.envUint("SOURCE_EID"));
    uint32 destEid = uint32(vm.envUint("DEST_EID"));
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
            sourceEid,
            destEid,
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

        (bytes32 id, uint64 nonce,) = OrderHelper.createOrder(hub, destEid, orderRequest, permits, signature, 0);

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
