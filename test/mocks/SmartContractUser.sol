// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Root} from "../../src/Validator.sol";
import {Validator} from "../../src/Validator.sol";
import {OrderHub} from "../../src/OrderHub.sol";

contract SmartContractUser {
    function approve(IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function createOrder(
        OrderHub orderhub,
        Root.OrderRequest memory request,
        bytes[] memory permits,
        bytes memory signature
    ) external {
        orderhub.createOrder(request, permits, signature);
    }

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4 magicValue) {
        return 0x1626ba7e;
    }
}
