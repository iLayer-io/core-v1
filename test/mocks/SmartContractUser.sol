// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BaseRouter} from "../../src/routers/BaseRouter.sol";
import {Root} from "../../src/Validator.sol";
import {Validator} from "../../src/Validator.sol";
import {OrderHub} from "../../src/OrderHub.sol";

contract SmartContractUser {
    using OptionsBuilder for bytes;

    uint32 public constant aEid = 1;
    uint32 public constant bEid = 2;

    bytes4 public signature = 0x1626ba7e;

    function setSignature(bytes4 newSignature) external {
        signature = newSignature;
    }

    function approve(IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function createOrder(
        OrderHub orderhub,
        Root.OrderRequest memory request,
        bytes[] memory permits,
        bytes memory _signature,
        bytes memory options,
        uint256 fee,
        BaseRouter.Bridge bridgeSelector
    ) external {
        //bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0);
        orderhub.createOrder{value: fee}(request, permits, _signature, bridgeSelector, options);
    }

    function isValidSignature(bytes32, bytes memory) external view returns (bytes4 magicValue) {
        return signature;
    }
}
