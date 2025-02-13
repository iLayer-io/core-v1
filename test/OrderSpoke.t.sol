// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {BaseTest} from "./BaseTest.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

error RestrictedToPrimaryFiller();
error OrderExpired();
error OrderCannotBeFilled();
error OrderPrimaryFillerExpired();

event TokenSweep(address indexed token, address indexed caller, uint256 amount);

/**
 * @title TargetContract
 * @notice A simple contract used for testing purposes.
 */
contract TargetContract {
    uint256 public bar = 0;

    /**
     * @notice Sets the value of bar.
     * @param val The new value for bar.
     */
    function foo(uint256 val) external {
        bar = val;
    }
}

/**
 * @title OrderSpokeTest
 * @notice Contains tests for order filling, including various edge cases.
 */
contract OrderSpokeTest is BaseTest {
    TargetContract public immutable target;

    constructor() BaseTest() {
        target = new TargetContract();
    }

    /**
     * @notice Tests filling an order for an ERC20 token swap.
     * @param inputAmount The amount of input tokens.
     * @param outputAmount The amount of output tokens.
     */
    function testFillOrder(uint256 inputAmount, uint256 outputAmount) public {
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.transfer(address(spoke), outputAmount);

        MessagingReceipt memory receipt = fillOrder(order, nonce, 0, 0, filler);
        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();

        assertEq(receipt.nonce, nonce);
    }

    /**
     * @notice Tests filling an order with an ERC721 token as the output.
     */
    function testFillOrderWithERC721Output() public {
        address filler = user1;
        uint256 inputAmount = 1 ether;
        MockERC721 outputToken = inputERC721Token;
        uint256 outputAmount = 1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");

        vm.startPrank(filler);
        outputToken.mint(filler);
        outputToken.transfer(address(spoke), 1);

        assertEq(outputToken.balanceOf(address(spoke)), 1);
        assertEq(outputToken.balanceOf(user0), 0);

        fillOrder(order, nonce, 0, 0, filler);

        assertEq(outputToken.balanceOf(filler), 0);
        assertEq(outputToken.balanceOf(address(spoke)), 0);
        assertEq(outputToken.balanceOf(user0), 1);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order with an invalid filler reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testFillOrderWithInvalidFiller() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;
        address invalidFiller = user2;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount, "Input token not transferred to Hub");

        outputToken.mint(invalidFiller, outputAmount);

        vm.startPrank(invalidFiller);
        outputToken.transfer(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(RestrictedToPrimaryFiller.selector);
        fillOrder(order, nonce, 0, 0, invalidFiller);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order after its deadline reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testFillOrderWithExpiredDeadline() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(OrderExpired.selector);
        fillOrder(order, nonce, 0, 0, filler);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order after the primary filler deadline reverts for the original filler and works for another.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testFillOrderWithExpiredPrimaryFillerDeadline() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 minutes);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        vm.expectRevert();
        vm.expectRevert(OrderCannotBeFilled.selector);
        fillOrder(order, nonce, 0, 0, filler);
        vm.stopPrank();

        vm.startPrank(user2);
        outputToken.mint(user2, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        fillOrder(order, nonce, 0, 0, user2);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an already filled order reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testFillOrderWithOrderAlreadyFilled() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 ether;
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.transfer(address(spoke), outputAmount);

        fillOrder(order, nonce, 0, 0, filler);
        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);

        vm.expectRevert();
        vm.expectRevert(OrderCannotBeFilled.selector);
        fillOrder(order, nonce, 0, 0, filler);
        vm.stopPrank();
    }

    /**
     * @notice Tests that filling an order with insufficient output token amount reverts.
     */
    /// forge-config: default.allow_internal_expect_revert = true
    function testFillOrderWithInsufficientAmount() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        uint256 insufficientAmount = outputAmount - 1e17;

        vm.startPrank(filler);
        outputToken.mint(filler, insufficientAmount);
        outputToken.approve(address(spoke), insufficientAmount);

        vm.expectRevert();
        vm.expectRevert(OrderCannotBeFilled.selector);
        fillOrder(order, nonce, 0, 0, filler);
        vm.stopPrank();
    }

    /**
     * @notice Tests filling an order that includes callData.
     * @param inputAmount The amount of input tokens.
     * @param outputAmount The amount of output tokens.
     */
    function testFillOrderWithCalldata(uint256 inputAmount, uint256 outputAmount) public {
        address filler = user1;

        Root.Order memory order = buildOrder(
            user0, filler, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );

        order.callData = "0x1234";

        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);

        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.transfer(address(spoke), outputAmount);

        fillOrder(order, nonce, 0, 0, filler);
        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();
    }

    /**
     * @notice Tests sweeping tokens from the spoke contract.
     */
    function testSweepTokens() public {
        uint256 inputAmount = 1 ether;

        inputToken.mint(user0, inputAmount);

        vm.prank(user0);
        inputToken.transfer(address(spoke), 0.5 ether);

        assertEq(inputToken.balanceOf(address(spoke)), 0.5 ether);

        spoke.sweep(user1, address(inputToken));

        assertEq(inputToken.balanceOf(user0), 0.5 ether);
        assertEq(inputToken.balanceOf(address(spoke)), 0);
        assertEq(inputToken.balanceOf(user1), 0.5 ether);
    }
}
