// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

library LayerZeroHelper {
    error UnsupportedChain();

    function getEid(uint32 chainId) external pure returns (uint32) {
        if (
            chainId == 42161 // Arbitrum
        ) {
            return 30110;
        }
        if (
            chainId == 8453 // Base
        ) {
            return 30184;
        }
        if (
            chainId == 56 // BSC
        ) {
            return 30102;
        }
        if (
            chainId == 1 // Ethereum mainnet
        ) {
            return 30101;
        }
        if (
            chainId == 146 // Sonic
        ) {
            return 30332;
        }
        if (
            chainId == 137 // Polygon
        ) {
            return 30109;
        }
        if (
            chainId == 10 // Optimism
        ) {
            return 30111;
        }
        if (
            chainId == 59144 // Linea
        ) {
            return 30183;
        }

        revert UnsupportedChain();
    }
}
