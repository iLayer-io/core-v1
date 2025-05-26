// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {OrderHelper} from "../../src/libraries/OrderHelper.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {LzRouter} from "../../src/routers/LzRouter.sol";
import {TargetContract} from "../mocks/TargetContract.sol";

contract LzRouterTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public constant aEid = 1;
    uint32 public constant bEid = 2;
    TargetContract public target;
    LzRouter public routerA;
    LzRouter public routerB;

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        routerA =
            LzRouter(_deployOApp(type(LzRouter).creationCode, abi.encode(address(this), address(endpoints[aEid]))));
        routerB =
            LzRouter(_deployOApp(type(LzRouter).creationCode, abi.encode(address(this), address(endpoints[bEid]))));
        target = new TargetContract(address(this), address(routerB));

        address[] memory oapps = new address[](2);
        oapps[0] = address(routerA);
        oapps[1] = address(routerB);
        this.wireOApps(oapps);

        routerA.setLzEid(bEid, bEid);
    }

    function testCorrectlyRoutesMsg() external {
        uint256 amt = 1000;
        target.foo(1);
        assertEq(target.bar(), 1);

        (uint256 fee, bytes memory options) = OrderHelper.getCreationLzData(address(routerA), bEid);
        IRouter.Message memory message = IRouter.Message({
            bridge: IRouter.Bridge.LAYERZERO,
            chainId: bEid,
            destination: BytesUtils.addressToBytes32(address(target)),
            payload: abi.encode(amt),
            extra: options,
            sender: BytesUtils.addressToBytes32(address(this))
        });
        routerA.send{value: fee * 10}(message);
        verifyPackets(bEid, BytesUtils.addressToBytes32(address(routerB)));
        assertEq(target.bar(), amt);
    }
}
