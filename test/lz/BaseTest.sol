// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {OrderHelper} from "../../src/libraries/OrderHelper.sol";
import {BaseRouter} from "../../src/routers/BaseRouter.sol";
import {LzRouter} from "../../src/routers/LzRouter.sol";
import {Root} from "../../src/Root.sol";
import {OrderHub} from "../../src/OrderHub.sol";
import {OrderSpoke} from "../../src/OrderSpoke.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {SmartContractUser} from "../mocks/SmartContractUser.sol";

/**
 * @title BaseTest
 * @notice Sets up the testing environment for order processing by deploying mock token contracts,
 * the OrderHub, OrderSpoke contracts, and providing helper functions to build, sign, and fill orders.
 */
contract BaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public constant aEid = 1;
    uint32 public constant bEid = 2;

    uint8 public constant NULL_BRIDGE = 0;
    uint8 public constant LAYERZERO_BRIDGE = 1;

    bytes[] public permits;
    bytes[] public permits2;

    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    LzRouter public routerA;
    LzRouter public routerB;
    OrderHub public hub;
    OrderSpoke public spoke;
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
    }

    /**
     * @notice Sets up endpoints and deploys the OrderHub and OrderSpoke contracts, wires the OApps,
     * and sets the maximum order deadline.
     */
    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        routerA =
            LzRouter(_deployOApp(type(LzRouter).creationCode, abi.encode(address(this), address(endpoints[aEid]))));
        routerB =
            LzRouter(_deployOApp(type(LzRouter).creationCode, abi.encode(address(this), address(endpoints[bEid]))));

        address[] memory oapps = new address[](2);
        oapps[0] = address(routerA);
        oapps[1] = address(routerB);
        this.wireOApps(oapps);

        routerA.setLzEid(bEid, bEid);
        routerB.setLzEid(aEid, aEid);

        hub = new OrderHub(address(this), address(routerA), address(0), 1 days, 0);
        spoke = new OrderSpoke(address(this), address(routerB));

        routerA.setWhitelisted(address(hub), true);
        routerB.setWhitelisted(address(spoke), true);

        vm.label(address(hub), "HUB");
        vm.label(address(spoke), "SPOKE");
        vm.label(address(spoke.executor()), "EXECUTOR");

        hub.setMaxOrderDeadline(1 days);
        hub.setSpokeAddress(bEid, BytesUtils.addressToBytes32(address(spoke)));
        spoke.setHubAddress(aEid, BytesUtils.addressToBytes32(address(hub)));
    }

    function _getCreationLzData() internal view returns (uint256 fee, bytes memory options) {
        return OrderHelper.getCreationLzData(address(routerA), bEid);
    }

    function _getSettlementLzData(Root.Order memory order, uint64 orderNonce, bytes32 hubFundingWallet)
        internal
        view
        returns (uint256 fee, bytes memory options)
    {
        return OrderHelper.getSettlementLzData(address(routerB), aEid, order, orderNonce, hubFundingWallet);
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
            aEid,
            bEid,
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
            sourceChainId: aEid,
            destinationChainId: bEid,
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + primaryFillerDeadlineOffset),
            deadline: uint64(block.timestamp + deadlineOffset),
            callRecipient: callRecipient,
            callData: callData,
            callValue: callValue
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: uint64(block.timestamp + 1 days)});
    }

    /**
     * @notice Builds an order request for an ERC721 input with an ERC20 output.
     * @param user The order creator's address.
     * @param filler The order filler's address.
     * @param fromToken The ERC721 token address.
     * @param fromTokenId The ERC721 token ID.
     * @param inputAmount The ERC721 token amount (typically 1).
     * @param toToken The ERC20 token address.
     * @param outputAmount The ERC20 token amount.
     * @return A Root.OrderRequest representing the constructed order request.
     */
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
            sourceChainId: aEid,
            destinationChainId: bEid,
            sponsored: false,
            primaryFillerDeadline: 1 hours,
            deadline: 1 days,
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: type(uint64).max});
    }

    /**
     * @notice Builds an order request for an ERC1155 input with an ERC20 output.
     * @param user The order creator's address.
     * @param filler The order filler's address.
     * @param fromToken The ERC1155 token address.
     * @param fromTokenIds The ERC1155 token IDs.
     * @param inputAmount The ERC1155 token amount.
     * @param toToken The ERC20 token address.
     * @param outputAmount The ERC20 token amount.
     * @return A Root.OrderRequest representing the constructed order request.
     */
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
            sourceChainId: aEid,
            destinationChainId: bEid,
            sponsored: false,
            primaryFillerDeadline: 1 hours,
            deadline: 1 days,
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: type(uint64).max});
    }

    /**
     * @notice Builds an order request for an ERC1155 batch input with an ERC20 output.
     * @param user The order creator's address.
     * @param filler The order filler's address.
     * @param fromToken The ERC1155 token address.
     * @param fromTokenIds The ERC1155 token IDs.
     * @param amounts The amounts for each ERC1155 token.
     * @param toToken The ERC20 token address.
     * @param outputAmount The ERC20 token amount.
     * @return A Root.OrderRequest representing the constructed order request.
     */
    function buildERC1155BatchOrderRequest(
        bytes32 user,
        bytes32 filler,
        address fromToken,
        uint256[] memory fromTokenIds,
        uint256[] memory amounts,
        address toToken,
        uint256 outputAmount
    ) public returns (Root.OrderRequest memory) {
        require(fromTokenIds.length == amounts.length, "IDs and amounts must have the same length");

        Root.Token[] memory inputs = new Root.Token[](fromTokenIds.length);
        for (uint256 i = 0; i < fromTokenIds.length; i++) {
            inputs[i] = Root.Token({
                tokenType: Root.Type.SEMI_FUNGIBLE_TOKEN,
                tokenAddress: BytesUtils.addressToBytes32(fromToken),
                tokenId: fromTokenIds[i],
                amount: amounts[i]
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
            sourceChainId: aEid,
            destinationChainId: bEid,
            sponsored: false,
            primaryFillerDeadline: 1 hours,
            deadline: 1 days,
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: type(uint64).max});
    }

    /**
     * @notice Generates an EIP-712 signature for an order request.
     * @param request The order request to sign.
     * @param user_pk The private key of the signer.
     * @return A 65-byte signature (r, s, v) of the order.
     */
    function buildSignature(Root.OrderRequest memory request, uint256 user_pk) public view returns (bytes memory) {
        bytes32 structHash = hub.hashOrderRequest(request);
        bytes32 domainSeparator = hub.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /**
     * @notice Validates that an order was successfully filled.
     * @param user The order creator's address.
     * @param filler The order filler's address.
     * @param inputAmount The expected input token amount.
     * @param outputAmount The expected output token amount.
     */
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

    function createOrder(
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue
    ) public payable returns (bytes32 orderId, uint64 nonce) {
        (bytes32 _orderId, uint64 _nonce) = OrderHelper.createOrder(
            address(routerA), hub, bEid, orderRequest, _permits, signature, gasValue, LAYERZERO_BRIDGE
        );

        verifyPackets(bEid, BytesUtils.addressToBytes32(address(routerB)));

        return (_orderId, _nonce);
    }

    function createOrderExpectRevert(
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue
    ) public {
        (uint256 fee, bytes memory options) = _getCreationLzData();

        vm.expectRevert();
        hub.createOrder{value: fee + gasValue}(orderRequest, _permits, signature, LAYERZERO_BRIDGE, options);
    }

    function fillOrder(Root.Order memory order, uint64 nonce, uint256 maxGas, address filler) public payable {
        vm.chainId(bEid);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getSettlementLzData(order, nonce, fillerEncoded);

        spoke.fillOrder{value: fee + order.callValue}(
            order, nonce, fillerEncoded, maxGas, BaseRouter.Bridge.LAYERZERO, options
        );
        verifyPackets(aEid, BytesUtils.addressToBytes32(address(routerA)));

        vm.chainId(aEid);
    }
}
