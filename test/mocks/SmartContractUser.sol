// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Validator} from "../../src/Validator.sol";
import {OrderHub} from "../../src/OrderHub.sol";

contract SmartContractUser {
    function approve(IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function createOrder(
        OrderHub orderhub,
        Validator.Order memory order,
        bytes[] memory permits,
        bytes memory signature
    ) external {
        OrderHub.OrderRequest memory request =
            OrderHub.OrderRequest({order: order, deadline: uint64(block.timestamp + 1 days), nonce: 1});
        orderhub.createOrder(request, permits, signature);
    }

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4 magicValue) {
        return 0x1626ba7e;
    }
}
