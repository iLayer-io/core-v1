// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {BaseRouter} from "../routers/BaseRouter.sol";
import {LzRouter} from "../routers/LzRouter.sol";
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
            tokenType: Root.Type.FUNGIBLE_TOKEN,
            tokenAddress: BytesUtils.addressToBytes32(fromToken),
            tokenId: 0,
            amount: inputAmount
        });

        outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.FUNGIBLE_TOKEN,
            tokenAddress: BytesUtils.addressToBytes32(toToken),
            tokenId: 0,
            amount: outputAmount
        });
    }

    /**
     * @notice Builds an order request for an ERC20 token swap.
     * @param sourceId The source chain ID.
     * @param destId The destination chain ID.
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
        uint32 sourceId,
        uint32 destId,
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
            sourceChainId: sourceId,
            destinationChainId: destId,
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
     * @param router The local router contract.
     * @param sourceId The source chain ID.
     * @param order The order to be processed.
     * @param orderNonce The order nonce.
     * @param hubFundingWallet The hub funding wallet encoded as bytes32.
     * @return fee The estimated fee for messaging.
     * @return options The options payload for the LayerZero messaging.
     */
    function getSettlementLzData(
        address router,
        uint32 sourceId,
        Root.Order memory order,
        uint64 orderNonce,
        bytes32 hubFundingWallet
    ) public view returns (uint256 fee, bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        payload = abi.encode(address(1), payload);
        fee = LzRouter(router).estimateLzBridgingFee(sourceId, payload, options);
    }

    /**
     * @notice Retrieves messaging fee and options data required for order settlement.
     * @param router The local router contract.
     * @param destId The destination chain ID.
     * @return fee The estimated fee for messaging.
     * @return options The options payload for the LayerZero messaging.
     */
    function getCreationLzData(address router, uint32 destId) public view returns (uint256 fee, bytes memory options) {
        options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        bytes memory payload = abi.encode(bytes32(0)); // pass a random bytes32 field
        payload = abi.encode(address(1), payload);
        fee = LzRouter(router).estimateLzBridgingFee(destId, payload, options);
    }

    /**
     * @notice Creates an order.
     * @param router The local router contract.
     * @param hub The order hub contract.
     * @param destId The destination chain ID.
     * @param orderRequest The order to create.
     * @param _permits The token permits.
     * @param signature The order signature.
     * @param gasValue The extra gas to supply;
     * @param bridgeSelector The bridge to route the message with.
     */
    function createOrder(
        address router,
        OrderHub hub,
        uint32 destId,
        Root.OrderRequest memory orderRequest,
        bytes[] memory _permits,
        bytes memory signature,
        uint256 gasValue,
        uint8 bridgeSelector
    ) public returns (bytes32 orderId, uint64 nonce) {
        bytes32 _orderId;
        uint64 _nonce;

        BaseRouter.Bridge bridge = BaseRouter.Bridge(bridgeSelector);

        if (bridge == BaseRouter.Bridge.LAYERZERO) {
            (uint256 fee, bytes memory options) = getCreationLzData(router, destId);
            (_orderId, _nonce) =
                hub.createOrder{value: fee + gasValue}(orderRequest, _permits, signature, bridgeSelector, options);
        } else {
            (_orderId, _nonce) = hub.createOrder{value: gasValue}(orderRequest, _permits, signature, bridgeSelector, "");
        }

        return (_orderId, _nonce);
    }

    /**
     * @notice Fills an order by invoking fillOrder on the OrderSpoke contract.
     * @param router The local router contract.
     * @param spoke The spoke contract.
     * @param sourceId The source chain ID.
     * @param order The order to fill.
     * @param nonce The order nonce.
     * @param maxGas The maximum gas limit for order processing.
     * @param filler The order filler's address.
     * @param bridgeSelector The bridge to route the message with.
     */
    function fillOrder(
        address router,
        OrderSpoke spoke,
        uint32 sourceId,
        Root.Order memory order,
        uint64 nonce,
        uint256 maxGas,
        address filler,
        BaseRouter.Bridge bridgeSelector
    ) public {
        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);

        if (bridgeSelector == BaseRouter.Bridge.LAYERZERO) {
            (uint256 fee, bytes memory options) = getSettlementLzData(router, sourceId, order, nonce, fillerEncoded);
            spoke.fillOrder{value: fee + order.callValue}(order, nonce, fillerEncoded, maxGas, bridgeSelector, options);
        } else {
            spoke.fillOrder{value: order.callValue}(order, nonce, fillerEncoded, maxGas, bridgeSelector, "");
        }
    }
}
