<h1 align="center">iLayer V1</h1>

<div align="center">

![Solidity](https://img.shields.io/badge/Solidity-0.8.24-e6e6e6?style=for-the-badge&logo=solidity&logoColor=black)

[![Discord](https://img.shields.io/badge/Discord-7289DA?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/xxx)
[![Twitter](https://img.shields.io/badge/Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://twitter.com/iLayer_io)
[![Website](https://img.shields.io/badge/Website-E34F26?style=for-the-badge&logo=Google-chrome&logoColor=white)](https://ilayer.io/)
[![Docs](https://img.shields.io/badge/Docs-7B36ED?style=for-the-badge&logo=gitbook&logoColor=white)](https://docs.ilayer.io/)

</div>

> iLayer is a cross-chain intent-based solver hub primitive.

This repository contains the core smart contracts for iLayer V1.

## Key Features

- Swap tokens from one chain to the other in a cheap and fast way.
- Bridge multiple tokens without needing to have gas on the destination chain.
- Access DeFi protocols without using their complex UX with one click.
- Easily build cross-chain interactions leveraging the iLayer infrastructure.

## Security

> Audit reports are available in the _audits_ folder.

The codebase comes with full test coverage, including unit, integration and fuzzy tests.

Smart contracts have been tested with the following automated tools:

- [slither](https://github.com/crytic/slither)
- [mythril](https://github.com/Consensys/mythril)
- [halmos](https://github.com/a16z/halmos)
- [olympix](https://www.olympix.ai)

If you find bugs, please report them to *info@ilayer.io*. You may be eligible for our bug bounty program that covers the deployed smart contracts.

## Documentation

You can read more about how it works on our [documentation website](https://docs.ilayer.io/) or on the [official whitepaper](https://github.com/ilayer-network/whitepaper/blob/master/ilayer-whitepaper.pdf).

## Deployment
To create a new instance of iLayer, you need to deploy the smart contracts on the desired EVM-compatible blockchain. It uses the AxLzRouter by default.
```bash
forge script script/DeployEVM.s.sol --rpc-url "$RPC_URL" --broadcast --slow --skip-simulation --private-key "$OWNER_PRIVATE_KEY" --sender "$OWNER" --verify --verifier etherscan
```

Then run the relevant scripts to setup the router.
For the LayerZero part:
```bash
forge script script/SetupLayerZeroEVM.s.sol --rpc-url "$RPC_URL" --broadcast --slow --skip-simulation --private-key "$OWNER_PRIVATE_KEY" --sender "$OWNER" --verify --verifier etherscan
```

## Licensing

The main license for the iLayer contracts is the Business Source License 1.1 (BUSL-1.1), see LICENSE file to learn more.
The Solidity files licensed under the BUSL-1.1 have appropriate SPDX headers.

## Disclaimer

This application is provided "as is" and "with all faults." We as developers makes no representations or warranties of
any kind concerning the safety, suitability, lack of viruses, inaccuracies, typographical errors, or other harmful
components of this software. There are inherent dangers in the use of any software, and you are solely responsible for
determining whether this software product is compatible with your equipment and other software installed on your
equipment. You are also solely responsible for the protection of your equipment and backup of your data, and THE
PROVIDER will not be liable for any damages you may suffer in connection with using, modifying, or distributing this
software product.
