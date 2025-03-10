# OrderHub-Spoke Multi-Chain Deployment

This repository provides a complete deployment procedure for deploying your OrderHub and OrderSpoke contracts on multiple chains using LayerZero. The process uses a deterministic deployment mechanism (via CREATE3) to ensure the same addresses on every chain, and then configures the contracts with chain‑specific settings (send/receive libraries, ULN, and Executor parameters) using the native `setConfig` functions.

## Overview

The deployment process consists of three main components:

1. **Configuration File (`config.yaml`):** Contains all chain‑specific configuration values such as RPC endpoints, send/receive library addresses, ULN (security) settings (with two required DVNs – one for LayerZero and one for Google), and Executor settings.
2. **Forge Deployment Script (`DeployHubSpoke.s.sol`):** A Solidity script using Forge's `Script` framework that deploys the OrderHub and OrderSpoke contracts via CREATE3 and configures them with the native LayerZero configuration calls.
3. **Shell Deployment Script (`deploy.sh`):** A Bash script that uses `yq` to parse `config.yaml`, exports chain‑specific environment variables, and iterates over all chains to run the Forge deployment script.

## Deployment Process

### Step 1: Set Up Your Environment

Export your deployer's private key:

```bash
export PRIVATE_KEY=0xYOUR_PRIVATE_KEY
```

### Step 2: Run the Deployment Script

Make the shell script executable and run it:

```sh
chmod +x run.sh
./run.sh
```

## Usefull Links

- [Default contracts](https://layerzeroscan.com/tools/defaults?version=V2)
