// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {SmartContractUser} from "./mocks/SmartContractUser.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * @title BaseTest
 * @notice Sets up the testing environment for order processing by deploying mock token contracts,
 * the OrderHub, OrderSpoke contracts, and providing helper functions to build, sign, and fill orders.
 */
contract BaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 public constant aEid = 1;
    uint32 public constant bEid = 2;

    bytes[] public permits;
    bytes[] public permits2;

    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    OrderHub public hub;
    OrderSpoke public spoke;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC721 public inputERC721Token;
    MockERC1155 public inputERC1155Token;
    SmartContractUser public contractUser;

    uint64 public requestNonce;

    /**
     * @notice Initializes the test environment by deploying mock token contracts, funding test user accounts,
     * and labeling addresses.
     */
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

        hub = OrderHub(_deployOApp(type(OrderHub).creationCode, abi.encode(address(endpoints[aEid]), 1 days, 0)));
        spoke = OrderSpoke(_deployOApp(type(OrderSpoke).creationCode, abi.encode(address(endpoints[bEid]))));

        address[] memory oapps = new address[](2);
        oapps[0] = address(hub);
        oapps[1] = address(spoke);
        this.wireOApps(oapps);

        vm.label(address(hub), "HUB");
        vm.label(address(spoke), "SPOKE");
        vm.label(address(spoke.executor()), "EXECUTOR");

        hub.setMaxOrderDeadline(1 days);
    }

    /**
     * @notice Retrieves messaging fee and options data required for order processing.
     * @param order The order to be processed.
     * @param orderNonce The order nonce.
     * @param hubFundingWallet The hub funding wallet encoded as bytes32.
     * @return fee The estimated fee for messaging.
     * @return options The options payload for the LayerZero messaging.
     */
    function _getLzData(Root.Order memory order, uint64 orderNonce, bytes32 hubFundingWallet)
        internal
        view
        returns (uint256 fee, bytes memory options)
    {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        fee = spoke.estimateFee(aEid, payload, options);
    }

    /**
     * @notice Formats token data into input and output token arrays.
     * @param fromToken The input token address.
     * @param inputAmount The input token amount.
     * @param toToken The output token address.
     * @param outputAmount The output token amount.
     * @return inputs An array of input tokens.
     * @return outputs An array of output tokens.
     */
    function _formatTokenStructs(address fromToken, uint256 inputAmount, address toToken, uint256 outputAmount)
        internal
        pure
        returns (Root.Token[] memory inputs, Root.Token[] memory outputs)
    {
        inputs = new Root.Token[](1);
        inputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(fromToken),
            tokenId: 0,
            amount: inputAmount
        });

        outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: 0,
            amount: outputAmount
        });
    }

    /**
     * @notice Builds an order request for an ERC20 token swap.
     * @param user The order creator's address.
     * @param filler The order filler's address.
     * @param fromToken The input token address.
     * @param inputAmount The input token amount.
     * @param toToken The output token address.
     * @param outputAmount The output token amount.
     * @param primaryFillerDeadlineOffset The primary filler deadline offset in seconds.
     * @param deadlineOffset The overall order deadline offset in seconds.
     * @return A Root.Order representing the constructed order.
     */
    function buildOrderRequest(
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset
    ) public returns (Root.OrderRequest memory) {
        (Root.Token[] memory inputs, Root.Token[] memory outputs) =
            _formatTokenStructs(fromToken, inputAmount, toToken, outputAmount);
        Root.Order memory order = Root.Order({
            user: BytesUtils.addressToBytes32(user),
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + primaryFillerDeadlineOffset),
            deadline: uint64(block.timestamp + deadlineOffset),
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return Root.OrderRequest({order: order, nonce: requestNonce++, deadline: uint64(block.timestamp + 1 days)});
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
        Root.Order memory order = Root.Order({
            user: BytesUtils.addressToBytes32(user),
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
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
            tokenType: Root.Type.ERC721,
            tokenAddress: BytesUtils.addressToBytes32(fromToken),
            tokenId: fromTokenId,
            amount: inputAmount
        });

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: type(uint256).max,
            amount: outputAmount
        });

        Root.Order memory order = Root.Order({
            user: user,
            filler: filler,
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
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
                tokenType: Root.Type.ERC1155,
                tokenAddress: BytesUtils.addressToBytes32(fromToken),
                tokenId: fromTokenIds[i],
                amount: inputAmount
            });
        }

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: 0,
            amount: outputAmount
        });

        Root.Order memory order = Root.Order({
            user: user,
            filler: filler,
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
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
                tokenType: Root.Type.ERC1155,
                tokenAddress: BytesUtils.addressToBytes32(fromToken),
                tokenId: fromTokenIds[i],
                amount: amounts[i]
            });
        }

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: 0,
            amount: outputAmount
        });

        Root.Order memory order = Root.Order({
            user: user,
            filler: filler,
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
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

    /**
     * @notice Fills an order by invoking fillOrder on the OrderSpoke contract.
     * @param order The order to fill.
     * @param nonce The order nonce.
     * @param maxGas The maximum gas limit for order processing.
     * @param filler The order filler's address.
     * @return The MessagingReceipt from the order fill.
     */
    function fillOrder(Root.Order memory order, uint64 nonce, uint256 maxGas, address filler)
        public
        payable
        returns (MessagingReceipt memory)
    {
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getLzData(order, nonce, fillerEncoded);

        MessagingReceipt memory receipt =
            spoke.fillOrder{value: fee + order.callValue}(order, nonce, fillerEncoded, maxGas, options);
        verifyPackets(aEid, BytesUtils.addressToBytes32(address(hub)));

        return receipt;
    }
}
