// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Root} from "./Root.sol";

contract Validator is Root, EIP712 {
    bytes32 public constant TOKEN_TYPEHASH =
        keccak256("Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)");

    bytes32 public constant ORDER_TYPEHASH = keccak256(
        abi.encodePacked(
            "Order(",
            "bytes32 user,",
            "bytes32 recipient,",
            "bytes32 filler,",
            "Token[] inputs,",
            "Token[] outputs,",
            "uint32 sourceChainId,",
            "uint32 destinationChainId,",
            "bool sponsored,",
            "uint64 primaryFillerDeadline,",
            "uint64 deadline,",
            "bytes32 callRecipient,",
            "bytes callData,",
            "uint256 callValue",
            ")",
            "Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)"
        )
    );

    bytes32 public constant ORDER_REQUEST_TYPEHASH = keccak256(
        abi.encodePacked(
            "OrderRequest(",
            "uint64 deadline,",
            "uint64 nonce,",
            "Order order",
            ")",
            "Order(",
            "bytes32 user,",
            "bytes32 recipient,",
            "bytes32 filler,",
            "Token[] inputs,",
            "Token[] outputs,",
            "uint32 sourceChainId,",
            "uint32 destinationChainId,",
            "bool sponsored,",
            "uint64 primaryFillerDeadline,",
            "uint64 deadline,",
            "bytes32 callRecipient,",
            "bytes callData,",
            "uint256 callValue",
            ")",
            "Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)"
        )
    );

    constructor() EIP712("iLayer", "1") {}

    function domainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTokenStruct(Token memory token) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(TOKEN_TYPEHASH, uint8(token.tokenType), token.tokenAddress, token.tokenId, token.amount)
        );
    }

    function hashTokenArray(Token[] memory tokens) internal pure returns (bytes32) {
        bytes32[] memory tokenHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenHashes[i] = hashTokenStruct(tokens[i]);
        }
        return keccak256(abi.encodePacked(tokenHashes));
    }

    function hashOrder(Order memory order) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.user, // bytes32 user
                order.recipient, // bytes32 recipient
                order.filler, // bytes32 filler
                hashTokenArray(order.inputs), // bytes32 hashed "Token[] inputs"
                hashTokenArray(order.outputs), // bytes32 hashed "Token[] outputs"
                order.sourceChainId, // uint32 sourceChainId
                order.destinationChainId, // uint32 destinationChainId
                order.sponsored, // bool sponsored
                order.primaryFillerDeadline, // uint64 primaryFillerDeadline
                order.deadline, // uint64 deadline
                order.callRecipient, // bytes32 callRecipient
                keccak256(order.callData), // hashed bytes callData
                order.callValue // uint256 callValue
            )
        );
    }

    function hashOrderRequest(OrderRequest memory request) public pure returns (bytes32) {
        bytes32 orderHash = hashOrder(request.order);

        return keccak256(
            abi.encode(
                ORDER_REQUEST_TYPEHASH,
                request.deadline, // uint64 deadline
                request.nonce, // uint64 nonce
                orderHash // Order order
            )
        );
    }

    function validateOrderRequest(OrderRequest memory request, bytes memory signature) public view returns (bool) {
        bytes32 structHash = hashOrderRequest(request);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));
        address orderRequestSigner = BytesUtils.bytes32ToAddress(request.order.user);
        return SignatureChecker.isValidSignatureNow(orderRequestSigner, digest, signature);
    }
}
