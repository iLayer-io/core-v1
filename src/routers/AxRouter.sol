// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AxelarExecutable} from "@axelar-network/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/contracts/interfaces/IAxelarGasService.sol";
import {IRouter} from "../interfaces/IRouter.sol";
import {IRouterCallable} from "../interfaces/IRouterCallable.sol";
import {BytesUtils} from "../libraries/BytesUtils.sol";

/**
 * @title Router contract for Axelar
 * @dev Helper to execute cross-chain contract calls
 * @custom:security-contact security@ilayer.io
 */
contract AxRouter is IRouter, AxelarExecutable, Ownable {
    IAxelarGasService public immutable gasService;
    mapping(uint32 chainId => string axChainStr) public chainIdToAxChainStr;
    mapping(string axChainStr => uint32 chainId) public AxChainStrToChainId;
    mapping(uint32 chainId => string router) public routers;

    event PeerRouterUpdated(uint32 indexed chainId, string indexed oldRouter, string indexed newRouter);
    event AxChainStrUpdated(uint32 indexed chainId, string indexed axChainStr);
    event MessageRoutedAx();

    error UnsupportedAxChain();
    error InvalidPeer();

    constructor(address _owner, address gateway_, address gasService_) Ownable(_owner) AxelarExecutable(gateway_) {
        gasService = IAxelarGasService(gasService_);
    }

    function setPeerRouter(uint32 chainId, string memory _router) external onlyOwner {
        emit PeerRouterUpdated(chainId, routers[chainId], _router);

        routers[chainId] = _router;
    }

    function setAxChainStr(uint32 chainId, string memory axChainStr) external onlyOwner {
        chainIdToAxChainStr[chainId] = axChainStr;
        AxChainStrToChainId[axChainStr] = chainId;

        emit AxChainStrUpdated(chainId, axChainStr);
    }

    function send(Message calldata message) external payable override(IRouter) {
        string memory destinationChain = chainIdToAxChainStr[message.chainId];
        if (bytes(destinationChain).length == 0) revert UnsupportedAxChain();

        string memory destinationAddress = routers[message.chainId];
        if (bytes(destinationAddress).length == 0) revert InvalidPeer();

        bytes memory payload = abi.encode(message.destination, message.payload);
        address refund = BytesUtils.bytes32ToAddress(message.sender);

        gasService.payNativeGasForContractCall{value: msg.value}(
            address(this), destinationChain, destinationAddress, payload, refund
        );

        gateway().callContract(destinationChain, destinationAddress, payload);

        emit MessageRoutedAx();
    }

    function _execute(bytes32, string calldata sourceChain, string calldata sourceAddress, bytes calldata payload)
        internal
        override
    {
        (address dest, bytes memory data) = abi.decode(payload, (address, bytes));
        uint32 srcChainId = AxChainStrToChainId[sourceChain];
        if (!Strings.equal(routers[srcChainId], sourceAddress)) revert InvalidPeer();

        IRouterCallable(dest).onMessageReceived(srcChainId, data);
    }
}
