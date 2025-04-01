// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Root} from "../Root.sol";
import {OrderHub} from "../OrderHub.sol";
import {OrderSpoke} from "../OrderSpoke.sol";
import {BytesUtils} from "./BytesUtils.sol";

library OrderHelper {
    using OptionsBuilder for bytes;

    /**
     * @notice Formats token data into input and output token arrays.
     * @param fromToken The input token address.
     * @param inputAmount The input token amount.
     * @param toToken The output token address.
     * @param outputAmount The output token amount.
     * @return inputs An array of input tokens.
     * @return outputs An array of output tokens.
     */
    function formatTokenStructs(address fromToken, uint256 inputAmount, address toToken, uint256 outputAmount)
        public
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
     * @param sourceEid The source chain's EID.
     * @param destEid The destination chain's EID.
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
        uint32 sourceEid,
        uint32 destEid,
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset
    ) public view returns (Root.OrderRequest memory) {
        (Root.Token[] memory inputs, Root.Token[] memory outputs) =
            formatTokenStructs(fromToken, inputAmount, toToken, outputAmount);
        // bytes32 usr = BytesUtils.addressToBytes32(user);
        Root.Order memory order = Root.Order({
            user: BytesUtils.addressToBytes32(user),
            recipient: BytesUtils.addressToBytes32(user),
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: sourceEid,
            destinationChainEid: destEid,
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + primaryFillerDeadlineOffset),
            deadline: uint64(block.timestamp + deadlineOffset),
            callRecipient: "",
            callData: "",
            callValue: 0
        });

        return
            Root.OrderRequest({order: order, nonce: uint64(block.number), deadline: uint64(block.timestamp + 1 days)});
    }

    /**
     * @notice Retrieves messaging fee and options data required for order settlement.
     * @param spoke The spoke contract.
     * @param sourceEid The source chain's EID.
     * @param order The order to be processed.
     * @param orderNonce The order nonce.
     * @param hubFundingWallet The hub funding wallet encoded as bytes32.
     * @return fee The estimated fee for messaging.
     * @return options The options payload for the LayerZero messaging.
     */
    function getSettlementL0Data(
        OrderSpoke spoke,
        uint32 sourceEid,
        Root.Order memory order,
        uint64 orderNonce,
        bytes32 hubFundingWallet
    ) public view returns (uint256 fee, bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        fee = spoke.estimateBridgingFee(sourceEid, payload, options);
    }

    /**
     * @notice Retrieves messaging fee and options data required for order settlement.
     * @param hub The hub contract.
     * @param destEid The destination chain's EID.
     * @return fee The estimated fee for messaging.
     * @return options The options payload for the LayerZero messaging.
     */
    function getCreationL0Data(OrderHub hub, uint32 destEid) public view returns (uint256 fee, bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        bytes memory payload = abi.encode(bytes32(0)); // pass a random bytes32 field
        fee = hub.estimateBridgingFee(destEid, payload, options);
    }

    /**
     * @notice Creates an order.
     * @param hub The order hub contract.
     * @param destEid The destination chain's EID.
     * @param orderRequest The order to create.
     * @param _permits The token permits.
     * @param signature The order signature.
     * @param gasValue The extra gas to supply;
     */
    function createOrder(
        OrderHub hub,
        uint32 destEid,
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue
    ) public returns (bytes32 orderId, uint64 nonce, MessagingReceipt memory) {
        (uint256 fee, bytes memory options) = getCreationL0Data(hub, destEid);
        (bytes32 _orderId, uint64 _nonce, MessagingReceipt memory receipt) =
            hub.createOrder{value: fee + gasValue}(orderRequest, _permits, signature, options);

        return (_orderId, _nonce, receipt);
    }

    /**
     * @notice Fills an order by invoking fillOrder on the OrderSpoke contract.
     * @param spoke The spoke contract.
     * @param sourceEid The source chain's EID.
     * @param order The order to fill.
     * @param nonce The order nonce.
     * @param maxGas The maximum gas limit for order processing.
     * @param filler The order filler's address.
     * @return The MessagingReceipt from the order fill.
     */
    function fillOrder(
        OrderSpoke spoke,
        uint32 sourceEid,
        Root.Order memory order,
        uint64 nonce,
        uint256 maxGas,
        address filler
    ) public returns (MessagingReceipt memory) {
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = getSettlementL0Data(spoke, sourceEid, order, nonce, fillerEncoded);

        MessagingReceipt memory receipt =
            spoke.fillOrder{value: fee + order.callValue}(order, nonce, fillerEncoded, maxGas, options);

        return receipt;
    }
}
