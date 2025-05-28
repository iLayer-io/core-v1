// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {OrderHelper} from "../src/libraries/OrderHelper.sol";
import {BaseRouter} from "../src/routers/BaseRouter.sol";

contract FillOrderScript is Script {
    address router = vm.envAddress("ROUTER");
    uint256 bridge = vm.envUint("BRIDGE");
    uint32 sourceChain = uint32(vm.envUint("SOURCE_CHAIN"));
    uint32 destChain = uint32(vm.envUint("DEST_CHAIN"));
    address user = vm.envAddress("USER");
    address filler = vm.envAddress("FILLER");
    uint256 fillerPrivateKey = vm.envUint("FILLER_PRIVATE_KEY");
    address fromToken = vm.envAddress("FROM_TOKEN");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    address toToken = vm.envAddress("TO_TOKEN");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint256 primaryFillerDeadlineOffset = vm.envUint("PRIMARY_FILLER_DEADLINE_OFFSET");
    uint256 deadlineOffset = vm.envUint("DEADLINE_OFFSET");
    address spokeAddr = vm.envAddress("SPOKE");
    uint64 nonce = uint64(vm.envUint("NONCE"));
    uint256 maxGas = vm.envUint("MAX_GAS");

    function run() external {
        vm.startBroadcast(fillerPrivateKey);

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
        OrderHelper.fillOrder(
            router,
            OrderSpoke(spokeAddr),
            sourceChain,
            orderRequest.order,
            nonce,
            maxGas,
            filler,
            BaseRouter.Bridge(bridge)
        );

        vm.stopBroadcast();
    }
}
