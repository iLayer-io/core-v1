// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {BaseRouter} from "../../src/routers/BaseRouter.sol";
import {NullRouter} from "../../src/routers/NullRouter.sol";
import {TargetContract} from "../mocks/TargetContract.sol";

contract NullRouterTest is Test {
    NullRouter public immutable router;
    TargetContract public immutable target;

    constructor() {
        router = new NullRouter(address(this));
        target = new TargetContract(address(this), address(router));
        router.setWhitelisted(address(target), true);
    }

    function testCorrectlyRoutesMsg(uint256 amt) external {
        BaseRouter.Message memory message = BaseRouter.Message({
            bridge: BaseRouter.Bridge.NULL,
            chainId: uint32(block.chainid),
            destination: BytesUtils.addressToBytes32(address(target)),
            payload: abi.encode(amt),
            extra: "",
            sender: BytesUtils.addressToBytes32(address(this))
        });

        // not whitelisted
        vm.expectRevert();
        router.send(message);

        router.setWhitelisted(address(this), true);
        router.send(message);
        assertEq(target.bar(), amt);
    }

    function testRevertsUnsupportedBridgingRoute() external {
        BaseRouter.Message memory message = BaseRouter.Message({
            bridge: BaseRouter.Bridge.NULL,
            chainId: uint32(block.chainid + 1),
            destination: BytesUtils.addressToBytes32(address(target)),
            payload: abi.encode(100),
            extra: "",
            sender: BytesUtils.addressToBytes32(address(this))
        });

        vm.expectRevert();
        router.send(message);
    }
}
