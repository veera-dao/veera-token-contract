# Verified Artifacts

This folder contains pre-compiled contract artifacts that have been verified and audited. These artifacts are intended to be used for all production deployments to ensure that the exact same bytecode is deployed across different chains and environments, regardless of local compiler versions or dependency changes.

## Contents

- `Veera.json`: The compiled artifact for the `Veera` token contract. This includes the ABI and the creation bytecode (without constructor arguments).

## Usage

To deploy using these artifacts, set the `ARTIFACT_PATH` environment variable when running the deployment scripts:

```bash
# Mainnet Deployment
ARTIFACT_PATH="verified-artifacts/Veera.json" ./scripts/deploy.sh

# Testnet Deployment
ARTIFACT_PATH="verified-artifacts/Veera.json" ./scripts/deploy-testnet.sh
```

The deployment script (`script/DeployVeera.s.sol`) will load the bytecode from this JSON file and dynamically append the constructor arguments defined in `deploy_manifest.json`. 

**Note:** If the `Veera.sol` source code is ever modified, this artifact must be regenerated to reflect those changes. However, for production releases, this artifact should be treated as the immutable source of truth for the contract bytecode.
