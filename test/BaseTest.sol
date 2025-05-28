// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {OrderHelper} from "../src/libraries/OrderHelper.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {BaseRouter} from "../src/routers/BaseRouter.sol";
import {NullRouter} from "../src/routers/NullRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {SmartContractUser} from "./mocks/SmartContractUser.sol";

contract BaseTest is Test {
    bytes[] public permits;
    bytes[] public permits2;
    uint32 public aChainId;
    uint32 public bChainId;

    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    OrderHub public hub;
    OrderSpoke public spoke;
    NullRouter public router;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC721 public inputERC721Token;
    MockERC1155 public inputERC1155Token;
    SmartContractUser public contractUser;
    uint64 public requestNonce;

    constructor() {
        permits = new bytes[](1);
        permits[0] = "";

        permits2 = new bytes[](2);
        permits2[0] = "";
        permits2[1] = "";

        aChainId = uint32(block.chainid);
        bChainId = uint32(block.chainid);

        inputToken = new MockERC20("input", "INPUT");
        inputERC721Token = new MockERC721("input", "INPUT");
        inputERC1155Token = new MockERC1155("input");
        outputToken = new MockERC20("output", "OUTPUT");
        contractUser = new SmartContractUser();

        deal(user0, 1 ether);
        deal(user1, 1 ether);
        deal(user2, 1 ether);

        vm.label(user0, "USER0");
        vm.label(user1, "USER1");
        vm.label(user2, "USER2");
        vm.label(address(this), "THIS");
        vm.label(address(contractUser), "CONTRACT USER");
        vm.label(address(inputToken), "INPUT TOKEN");
        vm.label(address(inputERC721Token), "INPUT ERC721 TOKEN");
        vm.label(address(inputERC1155Token), "INPUT ERC1155 TOKEN");
        vm.label(address(outputToken), "OUTPUT TOKEN");

        router = new NullRouter(address(this));
        hub = new OrderHub(address(this), address(router), address(0), 1 days, 0);
        spoke = new OrderSpoke(address(this), address(router));

        router.setWhitelisted(address(hub), true);
        router.setWhitelisted(address(spoke), true);

        vm.label(address(router), "ROUTER");
        vm.label(address(hub), "HUB");
        vm.label(address(spoke), "SPOKE");
        vm.label(address(spoke.executor()), "EXECUTOR");

        hub.setMaxOrderDeadline(1 days);
        hub.setSpokeAddress(uint32(block.chainid), BytesUtils.addressToBytes32(address(spoke)));
        spoke.setHubAddress(uint32(block.chainid), BytesUtils.addressToBytes32(address(hub)));
    }

    function buildOrderRequest(
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset
    ) public view returns (Root.OrderRequest memory) {
        return OrderHelper.buildOrderRequest(
            aChainId,
            bChainId,
            user,
            filler,
            fromToken,
            inputAmount,
            toToken,
            outputAmount,
            primaryFillerDeadlineOffset,
            deadlineOffset
        );
    }

    function buildBaseOrderRequest(
        Root.Token[] memory inputs,
        Root.Token[] memory outputs,
        address user,
        address filler,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset,
        bytes32 callRecipient,
        bytes memory callData,
        uint256 callValue
    ) public returns (Root.OrderRequest memory) {
        bytes32 usr = BytesUtils.addressToBytes32(user);
        Root.Order memory order = Root.Order({
            user: usr,
            recipient: usr,
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainId: aChainId,
            destinationChainId: bChainId,
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + primaryFillerDeadlineOffset),
            deadline: uint64(block.timestamp + deadlineOffset),
            callRecipient: callRecipient,
            callData: callData,
            callValue: callValue
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: uint64(block.timestamp + 1 days)});
    }

    function buildSignature(Root.OrderRequest memory request, uint256 user_pk) public view returns (bytes memory) {
        bytes32 structHash = hub.hashOrderRequest(request);
        bytes32 domainSeparator = hub.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function createOrder(
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue
    ) public payable returns (bytes32 orderId, uint64 nonce) {
        (bytes32 _orderId, uint64 _nonce) = OrderHelper.createOrder(
            address(router), hub, bChainId, orderRequest, _permits, signature, gasValue, BaseRouter.Bridge.NULL
        );

        return (_orderId, _nonce);
    }

    function createOrderExpectRevert(
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue
    ) public {
        vm.expectRevert();
        hub.createOrder{value: gasValue}(orderRequest, _permits, signature, BaseRouter.Bridge.NULL, "");
    }

    function buildERC721OrderRequest(
        bytes32 user,
        bytes32 filler,
        address fromToken,
        uint256 fromTokenId,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount
    ) public returns (Root.OrderRequest memory) {
        Root.Token[] memory inputs = new Root.Token[](1);
        inputs[0] = Root.Token({
            tokenType: Root.Type.NON_FUNGIBLE_TOKEN,
            tokenAddress: BytesUtils.addressToBytes32(fromToken),
            tokenId: fromTokenId,
            amount: inputAmount
        });

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.FUNGIBLE_TOKEN,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: type(uint256).max,
            amount: outputAmount
        });

        Root.Order memory order = Root.Order({
            user: user,
            recipient: user,
            filler: filler,
            inputs: inputs,
            outputs: outputs,
            sourceChainId: aChainId,
            destinationChainId: bChainId,
            sponsored: false,
            primaryFillerDeadline: 1 hours,
            deadline: 1 days,
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: type(uint64).max});
    }

    function buildERC1155OrderRequest(
        bytes32 user,
        bytes32 filler,
        address fromToken,
        uint256[] memory fromTokenIds,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount
    ) public returns (Root.OrderRequest memory) {
        Root.Token[] memory inputs = new Root.Token[](fromTokenIds.length);
        for (uint256 i = 0; i < fromTokenIds.length; i++) {
            inputs[i] = Root.Token({
                tokenType: Root.Type.SEMI_FUNGIBLE_TOKEN,
                tokenAddress: BytesUtils.addressToBytes32(fromToken),
                tokenId: fromTokenIds[i],
                amount: inputAmount
            });
        }

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.FUNGIBLE_TOKEN,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: 0,
            amount: outputAmount
        });

        Root.Order memory order = Root.Order({
            user: user,
            recipient: user,
            filler: filler,
            inputs: inputs,
            outputs: outputs,
            sourceChainId: aChainId,
            destinationChainId: bChainId,
            sponsored: false,
            primaryFillerDeadline: 1 hours,
            deadline: 1 days,
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: type(uint64).max});
    }

    function fillOrder(Root.Order memory order, uint64 nonce, uint256 maxGas, address filler) public payable {
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        spoke.fillOrder{value: order.callValue}(order, nonce, fillerEncoded, maxGas, BaseRouter.Bridge.NULL, "");
    }

    function fillOrderReverts(Root.Order memory order, uint64 nonce, uint256 maxGas, address filler) public payable {
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);

        vm.expectRevert();
        spoke.fillOrder{value: order.callValue}(order, nonce, fillerEncoded, maxGas, BaseRouter.Bridge.NULL, "");
    }

    function validateOrderWasFilled(address user, address filler, uint256 inputAmount, uint256 outputAmount)
        public
        view
    {
        assertEq(inputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        assertEq(outputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        assertEq(inputToken.balanceOf(user), 0, "User still holds input tokens");
        assertEq(outputToken.balanceOf(user), outputAmount, "User didn't receive output tokens");
        assertEq(inputToken.balanceOf(filler), inputAmount, "Filler didn't receive input tokens");
        assertEq(outputToken.balanceOf(filler), 0, "Filler still holds output tokens");
        assertEq(inputToken.balanceOf(address(spoke)), 0, "OrderSpoke contract is not empty");
        assertEq(outputToken.balanceOf(address(spoke)), 0, "OrderSpoke contract is not empty");
    }
}
