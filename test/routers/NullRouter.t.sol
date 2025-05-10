// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {NullRouter} from "../../src/routers/NullRouter.sol";
import {TargetContract} from "../mocks/TargetContract.sol";

contract NullRouterTest is Test {
    NullRouter public immutable router;
    TargetContract public immutable target;

    constructor() {
        router = new NullRouter();
        target = new TargetContract(address(this), address(router));
    }

    function testCorrectlyRoutesMsg(uint256 amt) external {
        IRouter.Message memory message = IRouter.Message({
            bridge: IRouter.Bridge.NULL,
            chainId: uint32(block.chainid),
            destination: BytesUtils.addressToBytes32(address(target)),
            payload: abi.encode(amt),
            extra: ""
        });
        router.send(message);
        assertEq(target.bar(), amt);
    }

    function testRevertsUnsupportedBridgingRoute() external {
        IRouter.Message memory message = IRouter.Message({
            bridge: IRouter.Bridge.NULL,
            chainId: uint32(block.chainid + 1),
            destination: BytesUtils.addressToBytes32(address(target)),
            payload: abi.encode(100),
            extra: ""
        });

        vm.expectRevert();
        router.send(message);
    }
}
