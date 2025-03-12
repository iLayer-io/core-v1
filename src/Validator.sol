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
            "bytes32 inputsHash,",
            "bytes32 outputsHash,",
            "uint32 sourceChainEid,",
            "uint32 destinationChainEid,",
            "bool sponsored,",
            "uint64 deadline,",
            "bytes32 callRecipient,",
            "bytes callData",
            "uint256 callValue",
            ")"
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
        bytes32 inputsHash = hashTokenArray(order.inputs);
        bytes32 outputsHash = hashTokenArray(order.outputs);

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.user, // bytes32 user
                inputsHash, // bytes32 inputsHash
                outputsHash, // bytes32 outputsHash
                order.sourceChainEid, // uint32 sourceChainEid
                order.destinationChainEid, // uint32 destinationChainEid
                order.sponsored, // bool sponsored
                order.deadline, // uint64 deadline
                order.callRecipient, // bytes32 callRecipient
                order.callValue, // uint256 callValue
                keccak256(order.callData) // hashed bytes callData
            )
        );
    }

    function validateOrder(Order memory order, bytes memory signature) public view returns (bool) {
        // 1. Hash the order into EIP712 struct hash
        bytes32 structHash = hashOrder(order);

        // 2. Build the final signed message per EIP-712
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator(), structHash));

        // 3. Recover or check signature against the user (cast from bytes32 -> address).
        address orderSigner = BytesUtils.bytes32ToAddress(order.user);
        //return isValidSignatureNow(orderSigner, digest, signature);
        return SignatureChecker.isValidSignatureNow(orderSigner, digest, signature);
    }
}
