# Verified Artifacts

This folder contains pre-compiled contract artifacts that have been verified and audited. These artifacts are intended to be used for all production deployments to ensure that the exact same bytecode is deployed across different chains and environments, regardless of local compiler versions or dependency changes.

## Contents

- `Veera.json`: The compiled artifact for the `Veera` token contract. This includes the ABI and the creation bytecode (without constructor arguments).

## Usage

To deploy using these artifacts, set the `TOKEN_ARTIFACT_PATH` and `BRIDGE_ARTIFACT_PATH` environment variables when running the deployment scripts:

```bash
# Mainnet Token Deployment
TOKEN_ARTIFACT_PATH="verified-artifacts/Veera.json" ./scripts/deploy.sh

# Mainnet Bridge Adapter Deployment
BRIDGE_ARTIFACT_PATH="verified-artifacts/VeeraMintBurnOFTAdapter.json" ./scripts/deploy-bridge.sh <rpc_url>

# Testnet Token Deployment
TOKEN_ARTIFACT_PATH="verified-artifacts/Veera.json" ./scripts/deploy-testnet.sh <rpc_url>
```

The token deployment script (`script/DeployVeera.s.sol`) will load the bytecode from `TOKEN_ARTIFACT_PATH` and dynamically append the constructor arguments defined in the manifest. The bridge adapter deployment script (`script/DeployOFTAdapter.s.sol`) will load the bytecode from `BRIDGE_ARTIFACT_PATH`.

**Note:** If the Solidity source code is ever modified, these artifacts must be regenerated. However, for production releases, they should be treated as the immutable source of truth for the contract bytecode.
