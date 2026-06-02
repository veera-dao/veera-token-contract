#!/usr/bin/env bash

# Mainnet Deployment Script (CREATE2 Deterministic Deployment)
# Deploys VeeraToken via CREATE2 to achieve the same contract address across chains.
#
# The broadcaster MUST be the Bootstrap Admin EOA defined in deploy_manifest.json.
# See README.md Section 2 for the full deterministic deployment workflow.
#
# Usage:
#   ./scripts/deploy.sh                        # Uses defaults from .env
#   RPC_URL=<url> ./scripts/deploy.sh          # Override RPC
#   DRY_RUN=true ./scripts/deploy.sh           # Simulate without broadcasting
#   ARTIFACT_PATH=<path> ./scripts/deploy.sh   # Use pre-compiled bytecode (e.g. out/Veera.sol/Veera.json)

set -euo pipefail

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ENV_FILE="${SCRIPT_PATH}/../.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# Support both RPC_URL (generic) and BASE_RPC_URL (legacy) env vars
RPC_URL="${RPC_URL:-${BASE_RPC_URL:-}}"

if [ -z "$RPC_URL" ]; then
    echo "❌ Error: RPC_URL (or BASE_RPC_URL) is not set in .env"
    exit 1
fi

if [ -z "${ETHERSCAN_API_KEY:-}" ]; then
    echo "❌ Error: ETHERSCAN_API_KEY is not set in .env"
    exit 1
fi

if [ -z "${DEPLOYER_ADDRESS:-}" ]; then
    echo "❌ Error: DEPLOYER_ADDRESS is not set in .env"
    echo "   This must match the bootstrapAdmin in deploy_manifest.json"
    exit 1
fi

if [ -z "${HARDWARE:-}" ]; then
    echo "❌ Error: HARDWARE is not set in .env (e.g. '--interactive', '--ledger', '--trezor')"
    exit 1
fi

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Install Foundry before running this script." >&2
  exit 1
fi

# Run manifest integrity check before deploying
echo "🔒 Running manifest integrity check..."
bash "${SCRIPT_PATH}/verify-manifest-checksum.sh"
echo ""

forge script "$SCRIPT_PATH/../script/DeployVeera.s.sol" \
  --rpc-url "$RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  ${HARDWARE}