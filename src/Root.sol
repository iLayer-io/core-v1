// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Root {
    using SafeERC20 for IERC20;

    enum Status {
        NULL,
        ACTIVE,
        FILLED,
        WITHDRAWN
    }

    enum Type {
        NULL,
        NATIVE,
        ERC20,
        ERC721,
        ERC1155
    }

    struct Token {
        Type tokenType;
        bytes32 tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    struct Order {
        bytes32 user;
        bytes32 recipient;
        bytes32 filler;
        Token[] inputs;
        Token[] outputs;
        uint32 sourceChainId;
        uint32 destinationChainId;
        bool sponsored;
        uint64 primaryFillerDeadline;
        uint64 deadline;
        bytes32 callRecipient;
        bytes callData;
        uint256 callValue;
    }

    struct OrderRequest {
        uint64 deadline;
        uint64 nonce;
        Order order;
    }

    error NativeTransferFailed();
    error UnsupportedTransfer();
    error InsufficientGasValue();

    function getOrderId(Order memory order, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(nonce, order));
    }

    function _transfer(Type tokenType, address from, address to, address token, uint256 id, uint256 amount) internal {
        if (tokenType == Type.ERC20) {
            if (from == address(this)) IERC20(token).safeTransfer(to, amount);
            else IERC20(token).safeTransferFrom(from, to, amount);
        } else if (tokenType == Type.NATIVE) {
            if (from == address(this)) {
                (bool success,) = to.call{value: amount}("");
                if (!success) revert NativeTransferFailed();
            } else {
                if (msg.value < amount) revert InsufficientGasValue();
                if (to != address(this)) {
                    (bool success,) = to.call{value: amount}("");
                    if (!success) revert NativeTransferFailed();
                }
            }
        } else if (tokenType == Type.ERC721) {
            IERC721(token).safeTransferFrom(from, to, id);
        } else if (tokenType == Type.ERC1155) {
            IERC1155(token).safeTransferFrom(from, to, id, amount, "");
        } else {
            revert UnsupportedTransfer();
        }
    }
}
