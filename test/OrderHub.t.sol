// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Root} from "../src/Root.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {BaseTest} from "./BaseTest.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

event ERC721Received(address operator, address from, uint256 tokenId, bytes data);

event ERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data);

event ERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data);

/**
 * @title OrderHubTest
 * @notice Contains tests for the OrderHub contract covering order creation, signature validation, withdrawal,
 * permit handling, deadlines, multiple orders, and replay attack prevention.
 */
contract OrderHubTest is BaseTest {
    constructor() BaseTest() {}

    /**
     * @notice Test order creation for an ERC20 token swap.
     * @param inputAmount The amount of input tokens.
     * @param outputAmount The amount of output tokens.
     * @return order The built order.
     */
    function testCreateOrder(uint256 inputAmount, uint256 outputAmount) public returns (Root.Order memory) {
        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            outputAmount,
            1 minutes,
            5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);
        address hubAddr = address(hub);
        assertEq(inputToken.balanceOf(hubAddr), 0);
        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount);
        vm.prank(user0);
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(hubAddr), inputAmount);
        return order;
    }

    /**
     * @notice Test order creation using an ERC20 permit.
     */
    function testCreateOrderWithPermit() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);
        assertTrue(hub.validateOrder(order, signature), "Invalid signature");

        uint256 nonce = inputToken.nonces(user0);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                inputToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(inputToken.PERMIT_TYPEHASH(), user0, address(hub), inputAmount, nonce, deadline))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user0_pk, permitHash);
        bytes memory permit = abi.encode(inputAmount, deadline, v, r, s);
        bytes[] memory permitsArray = new bytes[](1);
        permitsArray[0] = permit;

        inputToken.mint(user0, inputAmount);
        hub.createOrder(buildOrderRequest(order, 1), permitsArray, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
    }

    /**
     * @notice Test order creation with an ERC721 token as output.
     */
    function testCreateOrderWithERC721Output() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1;
        MockERC721 outputToken = inputERC721Token;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            outputAmount,
            1 minutes,
            5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);
        address hubAddr = address(hub);
        assertEq(inputToken.balanceOf(hubAddr), 0);
        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount);
        vm.prank(user0);
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(hubAddr), inputAmount);
    }

    /**
     * @notice Test the order withdrawal process.
     */
    function testOrderWithdrawal() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = testCreateOrder(inputAmount, 1);

        vm.warp(block.timestamp + 1 minutes);
        vm.startPrank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes);
        vm.startPrank(user1);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount);

        vm.prank(user0);
        hub.withdrawOrder(order, 1);
        assertEq(inputToken.balanceOf(address(hub)), 0);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    /**
     * @notice Test that double withdrawal of the same order fails.
     */
    function testDoubleWithdrawal() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = testCreateOrder(inputAmount, 1);
        vm.warp(block.timestamp + 5 minutes);

        vm.prank(user0);
        hub.withdrawOrder(order, 1);

        vm.startPrank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();
    }

    /**
     * @notice Test order creation failure due to insufficient token allowance.
     */
    function testCreateOrderInsufficientAllowance() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount - 1);

        vm.prank(user0);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    /**
     * @notice Test order creation failure when the order signature is invalid.
     */
    function testInvalidOrderSignature() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        order.deadline += 1;

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        vm.expectRevert();
        bytes[] memory emptyPermits = new bytes[](1);
        hub.createOrder(buildOrderRequest(order, 1), emptyPermits, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test order creation failure due to deadline mismatch.
     */
    function testOrderDeadlineMismatch() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 6 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test that order creation fails when the order has already expired.
     */
    function testOrderExpired() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.warp(block.timestamp + 6 minutes);
        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test order creation failure when the token balance is insufficient.
     */
    function testCreateOrderInsufficientBalance() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount - 1);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount);

        vm.prank(user0);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    /**
     * @notice Test withdrawal failure for a non-existent order.
     */
    function testWithdrawNonExistentOrder() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );

        vm.prank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
    }

    /**
     * @notice Test creation of multiple orders from the same user.
     */
    function testCreateMultipleOrdersSameUser(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Root.Order memory order1 = buildOrder(
            user0, address(this), address(inputToken), inputAmount1, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature1 = buildSignature(order1, user0_pk);

        Root.Order memory order2 = buildOrder(
            user0, address(this), address(inputToken), inputAmount2, address(outputToken), 2, 1 minutes, 5 minutes
        );
        bytes memory signature2 = buildSignature(order2, user0_pk);

        inputToken.mint(user0, inputAmount1 + inputAmount2);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount1 + inputAmount2);

        vm.startPrank(user0);
        hub.createOrder(buildOrderRequest(order1, 1), permits, signature1);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order2, 1), permits, signature2);
        hub.createOrder(buildOrderRequest(order2, 2), permits, signature2);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount1 + inputAmount2);
    }

    /**
     * @notice Test creation of multiple orders from different users.
     */
    function testCreateMultipleOrdersMultipleUsers(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Root.Order memory order1 = buildOrder(
            user1, address(this), address(inputToken), inputAmount1, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature1 = buildSignature(order1, user1_pk);

        Root.Order memory order2 = buildOrder(
            user2, address(this), address(inputToken), inputAmount2, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature2 = buildSignature(order2, user2_pk);

        vm.startPrank(user1);
        inputToken.mint(user1, inputAmount1);
        inputToken.approve(address(hub), inputAmount1);
        hub.createOrder(buildOrderRequest(order1, 1), permits, signature1);
        vm.stopPrank();

        vm.startPrank(user2);
        inputToken.mint(user2, inputAmount2);
        inputToken.approve(address(hub), inputAmount2);
        hub.createOrder(buildOrderRequest(order2, 1), permits, signature2);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount1 + inputAmount2);
    }

    /**
     * @notice Test order creation failure when using an invalid token address.
     */
    function testCreateOrderWithInvalidTokens() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 1e18;
        Validator.Order memory order = buildOrder(
            user1, address(this), address(0), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user1_pk);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    /**
     * @notice Test order creation via a smart contract user.
     */
    function testCreateOrderSmartContract(uint256 inputAmount) public {
        vm.assume(inputAmount > 0);
        Validator.Order memory order = buildOrder(
            address(contractUser),
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            1 minutes,
            5 minutes
        );
        bytes memory signature = "";

        inputToken.mint(address(contractUser), inputAmount);
        vm.prank(address(contractUser));
        inputToken.approve(address(hub), inputAmount);

        contractUser.createOrder(hub, order, permits, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
    }

    /**
     * @notice Test withdrawing multiple identical orders.
     */
    function testWithdrawMultipleIdenticalOrders() public {
        uint256 inputAmount = 1e18;
        Validator.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );

        inputToken.mint(user0, inputAmount * 2);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount * 2);
        bytes memory signature = buildSignature(order, user0_pk);

        vm.prank(user0);
        (bytes32 orderId1,) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
        vm.prank(user0);
        (bytes32 orderId2, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 2), permits, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount * 2);
        assertNotEq(orderId1, orderId2);
        vm.warp(block.timestamp + 10 minutes);

        vm.prank(user0);
        hub.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);

        vm.prank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    /**
     * @notice Test that order creation fails when the order deadline exceeds the maximum allowed.
     */
    function testMaxDeadline() public {
        uint64 maxDeadline = 1 hours;
        hub.setMaxOrderDeadline(maxDeadline);

        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2e18;
        Validator.Order memory order = buildOrder(
            user1,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            outputAmount,
            1 minutes,
            1 weeks
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.startPrank(user1);
        inputToken.mint(user1, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();
    }

    /**
     * @notice Test the time buffer functionality for order withdrawal.
     */
    function testTimeBuffer() public {
        uint64 timeBufferPeriod = 1 hours;
        hub.setTimeBuffer(timeBufferPeriod);

        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2e18;
        Validator.Order memory order = buildOrder(
            user0, user1, address(inputToken), inputAmount, address(outputToken), outputAmount, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);
        (, uint64 nonce) = hub.createOrder(buildOrderRequest(order, 1), permits, signature);

        vm.warp(block.timestamp + 4 minutes);
        vm.expectRevert();
        hub.withdrawOrder(order, nonce);

        vm.warp(block.timestamp + 2 minutes);
        vm.expectRevert();
        hub.withdrawOrder(order, nonce);

        vm.warp(block.timestamp + 1 hours);
        hub.withdrawOrder(order, nonce);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    /**
     * @notice Test updating the time buffer.
     */
    function testTimeBufferUpdate(uint64 timeBuffer) public {
        assertEq(hub.timeBuffer(), 0);
        hub.setTimeBuffer(timeBuffer);
        assertEq(hub.timeBuffer(), timeBuffer);

        vm.startPrank(user0);
        vm.expectRevert();
        hub.setTimeBuffer(2 hours);
        vm.stopPrank();
    }

    /**
     * @notice Test replay attack prevention.
     */
    function testReplyAttack() public {
        uint256 inputAmount = 1 ether;
        Validator.Order memory order = buildOrder(
            user0, address(this), address(inputToken), inputAmount, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, 10 * inputAmount);
        vm.prank(user0);
        inputToken.approve(address(hub), 10 * inputAmount);

        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);

        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
    }

    /**
     * @notice Test creation of an order with an ERC721 token.
     */
    function testCreateERC721Order() public {
        Validator.Order memory order = buildERC721Order(
            user0, address(this), address(inputERC721Token), 1, 1, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.prank(user0);
        inputERC721Token.mint(user0);

        vm.prank(user0);
        inputERC721Token.approve(address(hub), 1);

        assertEq(inputERC721Token.balanceOf(user0), 1);
        assertEq(inputERC721Token.balanceOf(address(hub)), 0);

        vm.prank(user0);
        vm.expectEmit(true, true, true, true);
        emit ERC721Received(address(hub), user0, 1, "");
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);

        assertEq(inputERC721Token.balanceOf(user0), 0);
        assertEq(inputERC721Token.balanceOf(address(hub)), 1);
    }

    /**
     * @notice Test creation of an order with an ERC1155 token.
     */
    function testCreateERC1155Order() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        Validator.Order memory order = buildERC1155Order(
            user0, address(this), address(inputERC1155Token), ids, 2, address(outputToken), 1, 1 minutes, 5 minutes
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.prank(user0);
        inputERC1155Token.mint(user0, 1, 2, "");

        vm.prank(user0);
        inputERC1155Token.setApprovalForAll(address(hub), true);

        assertEq(inputERC1155Token.balanceOf(user0, 1), 2);
        assertEq(inputERC1155Token.balanceOf(address(hub), 1), 0);

        vm.prank(user0);
        vm.expectEmit(true, true, true, true);
        emit ERC1155Received(address(hub), user0, 1, 2, "");
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);

        assertEq(inputERC1155Token.balanceOf(user0, 1), 0);
        assertEq(inputERC1155Token.balanceOf(address(hub), 1), 2);
    }
}
