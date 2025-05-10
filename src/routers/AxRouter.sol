// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AxelarExecutable} from "@axelar-network/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/contracts/interfaces/IAxelarGasService.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IRouterCallable} from "../interfaces/IRouterCallable.sol";

/**
 * @title Router contract for Axelar
 * @dev Helper to execute cross-chain contract calls
 * @custom:security-contact security@ilayer.io
 */
contract AxRouter is IRouter, AxelarExecutable {
    IAxelarGasService public immutable gasService;

    event MessageRoutedAx();

    error UnsupportedLzChain();

    constructor(address gateway_, address gasService_) AxelarExecutable(gateway_) {
        gasService = IAxelarGasService(gasService_);
    }

    function send(Message calldata message) external payable override(IRouter) {
        string memory destinationChain = Strings.toString(message.chainId);
        string memory destinationAddress = Strings.toHexString(uint256(message.destination));
        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this), destinationChain, destinationAddress, message.payload, msg.sender
        );

        gateway().callContract(destinationChain, destinationAddress, message.payload);

        emit MessageRoutedAx();
    }

    function _execute(
        bytes32,
        string calldata sourceChain,
        string calldata,
        bytes calldata payload
    ) internal override {
        (address dest, bytes memory data) = abi.decode(payload, (address, bytes));
        IRouterCallable(dest).onMessageReceived(uint32(Strings.parseUint(sourceChain)), data);
    }
}
