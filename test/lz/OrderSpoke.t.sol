// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {Root} from "../../src/Root.sol";
import {OrderHub} from "../../src/OrderHub.sol";
import {OrderSpoke} from "../../src/OrderSpoke.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {TargetContract} from "../mocks/TargetContract.sol";
import {BaseTest} from "./BaseTest.sol";

error RestrictedToPrimaryFiller();
error OrderExpired();
error OrderCannotBeFilled();

/**
 * @title OrderSpokeTest
 * @notice Contains tests for order filling, including various edge cases.
 */
contract OrderSpokeTest is BaseTest {
    TargetContract public immutable target;

    constructor() BaseTest() {
        target = new TargetContract(address(this), address(routerA));
    }

    function setUp() public override {
        super.setUp();

        vm.chainId(aEid);
    }

    /**
     * @notice Tests filling an order for an ERC20 token swap.
     * @param inputAmount The amount of input tokens.
     * @param outputAmount The amount of output tokens.
     */
    function testLzFillOrderBase(uint256 inputAmount, uint256 outputAmount) public {
        address filler = user1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (bytes32 orderID, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");
        assertTrue(spoke.orders(orderID) == OrderSpoke.OrderStatus.PENDING, "Order not registered by the spoke");

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        fillOrder(orderRequest.order, nonce, 0, filler);
        vm.stopPrank();

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
    }

    /**
     * @notice Tests a base order with a fee
     */
    function testLzFillOrderWithFee(uint256 inputAmount, uint256 outputAmount, uint16 fee) public {
        fee = uint16(bound(fee, 0, 10_000));
        outputAmount = bound(outputAmount, 0, type(uint256).max / 10_000);

        address filler = user1;
        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        spoke.setFee(fee);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (bytes32 orderID, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");
        assertTrue(spoke.orders(orderID) == OrderSpoke.OrderStatus.PENDING);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        fillOrder(orderRequest.order, nonce, 0, filler);

        uint256 feeAmount = outputAmount * fee / spoke.FEE_RESOLUTION();
        uint256 outputWithoutFee = outputAmount - feeAmount;

        assertEq(inputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        assertEq(outputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        assertEq(inputToken.balanceOf(user0), 0, "User still holds input tokens");
        assertEq(outputToken.balanceOf(user0), outputWithoutFee, "User didn't receive output tokens");
        assertEq(inputToken.balanceOf(filler), inputAmount, "Filler didn't receive input tokens");
        assertEq(outputToken.balanceOf(filler), 0, "Filler still holds output tokens");
        assertEq(inputToken.balanceOf(address(spoke)), 0, "OrderSpoke contract is not empty");
        assertEq(outputToken.balanceOf(address(spoke)), feeAmount, "OrderSpoke contract is not empty");

        vm.stopPrank();
    }

    /**
     * @notice Tests filling an order with an ERC721 token as the output.
     */
    function testLzFillOrderWithERC721Output() public {
        address filler = user1;
        uint256 inputAmount = 1 ether;
        MockERC721 outputToken = inputERC721Token;
        uint256 outputAmount = 1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(orderRequest, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");

        vm.startPrank(filler);
        outputToken.mint(filler);
        outputToken.approve(address(spoke), 1);

        fillOrder(orderRequest.order, nonce, 0, filler);

        assertEq(outputToken.balanceOf(filler), 0);
        assertEq(outputToken.balanceOf(user0), 1);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order with an invalid filler reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testLzFillOrderWithInvalidFiller() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;
        address invalidFiller = user2;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(orderRequest, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");

        outputToken.mint(invalidFiller, outputAmount);

        vm.startPrank(invalidFiller);
        outputToken.approve(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(RestrictedToPrimaryFiller.selector);
        fillOrder(orderRequest.order, nonce, 0, invalidFiller);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order after its deadline reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testLzFillOrderWithExpiredDeadline() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(orderRequest, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(OrderExpired.selector);
        fillOrder(orderRequest.order, nonce, 0, filler);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order after the primary filler deadline reverts for the original filler and works for another.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testLzFillOrderWithExpiredPrimaryFillerDeadline() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(orderRequest, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 minutes);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(OrderCannotBeFilled.selector);
        fillOrder(orderRequest.order, nonce, 0, filler);
        vm.stopPrank();

        vm.startPrank(user2);
        outputToken.mint(user2, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        fillOrder(orderRequest.order, nonce, 0, user2);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an already filled order reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testLzFillOrderWithOrderAlreadyFilled() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 ether;
        address filler = user1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        fillOrder(orderRequest.order, nonce, 0, filler);
        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getSettlementLzData(orderRequest.order, nonce, fillerEncoded);
        vm.expectRevert();
        spoke.fillOrder{value: fee}(orderRequest.order, nonce, fillerEncoded, 0, IRouter.Bridge.LAYERZERO, options);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order with insufficient output token amount reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testLzFillOrderWithInsufficientAmount() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        uint256 insufficientAmount = outputAmount - 1e17;

        vm.startPrank(filler);
        outputToken.mint(filler, insufficientAmount);
        outputToken.approve(address(spoke), insufficientAmount);

        vm.expectRevert();
        vm.expectRevert(OrderCannotBeFilled.selector);
        fillOrder(orderRequest.order, nonce, 0, filler);
        vm.stopPrank();
    }

    /**
     * @notice Test filling an order with native token in input and output
     */
    function testLzFillOrderWithNativeInputAndOutput() public {
        address filler = user1;
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 10 * 1e18;

        Root.Token[] memory inputs = new Root.Token[](1);
        inputs[0] = Root.Token({tokenType: Root.Type.NATIVE, tokenAddress: "", tokenId: 0, amount: inputAmount});

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({tokenType: Root.Type.NATIVE, tokenAddress: "", tokenId: 0, amount: outputAmount});

        Root.OrderRequest memory orderRequest =
            buildBaseOrderRequest(inputs, outputs, user0, filler, 1 minutes, 5 minutes, "", "", 0);
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        // create order
        vm.deal(user0, inputAmount + 300011508); // lz fee
        assertEq(address(hub).balance, 0);
        vm.prank(user0);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, inputAmount);
        assertEq(address(hub).balance, inputAmount);

        // fill order
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getSettlementLzData(orderRequest.order, nonce, fillerEncoded);
        uint256 extraGas = 100 ether;
        uint256 totalGas = outputAmount + fee + extraGas;
        vm.deal(filler, totalGas);

        vm.chainId(bEid);

        uint256 initialBalance = user0.balance;
        assertEq(address(spoke).balance, 0);
        vm.prank(filler);
        spoke.fillOrder{value: totalGas}(orderRequest.order, nonce, fillerEncoded, 0, IRouter.Bridge.LAYERZERO, options);
        verifyPackets(aEid, BytesUtils.addressToBytes32(address(routerA)));

        assertEq(address(spoke).balance, 0);
        assertEq(address(hub).balance, 0);
        assertEq(user0.balance, initialBalance + outputAmount);
    }

    /**
     * @notice Tests filling an order that includes callData.
     * @param inputAmount The amount of input tokens.
     * @param outputAmount The amount of output tokens.
     * @param gasValue The amount of gas to send to the target contract along with the order.
     */
    function testLzFillOrderWithCalldata(uint256 inputAmount, uint256 outputAmount, uint128 gasValue) public {
        address filler = user1;
        assertEq(target.bar(), 0);

        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        orderRequest.order.callRecipient = BytesUtils.addressToBytes32(address(target));
        orderRequest.order.callData = abi.encodeWithSelector(target.foo.selector, 1234);
        orderRequest.order.callValue = uint256(gasValue);
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = createOrder(orderRequest, permits, signature, 0);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        vm.chainId(bEid);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getSettlementLzData(orderRequest.order, nonce, fillerEncoded);

        uint256 extraGas = 0.01 ether;
        uint256 totalGas = orderRequest.order.callValue + fee + extraGas;
        vm.deal(filler, totalGas);
        spoke.fillOrder{value: totalGas}(
            orderRequest.order,
            nonce,
            fillerEncoded,
            orderRequest.order.callValue + extraGas,
            IRouter.Bridge.LAYERZERO,
            options
        );
        verifyPackets(aEid, BytesUtils.addressToBytes32(address(routerA)));

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();

        assertEq(target.bar(), 1234);
        assertEq(address(target).balance, gasValue);
    }

    /**
     * @notice Tests sweeping tokens from the spoke contract.
     */
    function testLzSweepTokens() public {
        uint256 inputAmount = 1 ether;

        inputToken.mint(user0, inputAmount);

        // ERC20 sweep
        vm.prank(user0);
        inputToken.transfer(address(spoke), 0.5 ether);

        assertEq(inputToken.balanceOf(address(spoke)), 0.5 ether);
        spoke.sweep(Root.Type.ERC20, 0, address(inputToken), user1, 0.5 ether);

        assertEq(inputToken.balanceOf(user0), 0.5 ether);
        assertEq(inputToken.balanceOf(address(spoke)), 0);
        assertEq(inputToken.balanceOf(user1), 0.5 ether);

        // native sweep
        vm.deal(address(spoke), 1 ether);
        assertEq(address(spoke).balance, 1 ether);

        uint256 initialBalance = user1.balance;
        spoke.sweep(Root.Type.NATIVE, 0, address(0), user1, 1 ether);

        assertEq(user1.balance, initialBalance + 1 ether);
        assertEq(address(spoke).balance, 0);
    }

    /**
     * @notice Test destination endpoint validation.
     */
    function testLzIncorrectChainEidRevert() public {
        address filler = user1;

        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2e18;
        Root.OrderRequest memory orderRequest = buildOrderRequest(
            user0, user1, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        orderRequest.order.destinationChainId = 5;
        bytes memory signature = buildSignature(orderRequest, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        createOrderExpectRevert(orderRequest, permits, signature, 0);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        uint64 nonce = 1;
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getSettlementLzData(orderRequest.order, nonce, fillerEncoded);
        vm.expectRevert();
        spoke.fillOrder{value: fee}(orderRequest.order, nonce, fillerEncoded, 0, IRouter.Bridge.LAYERZERO, options);
        vm.stopPrank();
    }
}
