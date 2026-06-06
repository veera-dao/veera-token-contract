#!/usr/bin/env bash

# Bridge Adapter Deployment Script (CREATE2 Deterministic Deployment)
# Deploys VeeraMintBurnOFTAdapter via CREATE2 to achieve deterministic addressing.
#
# Usage:
#   ./scripts/deploy-bridge.sh                               # Deploy with config from .env
#   ./scripts/deploy-bridge.sh <url>                         # Override RPC
#   DRY_RUN=true ./scripts/deploy-bridge.sh <url>            # Dry run / simulation
#   BRIDGE_ARTIFACT_PATH=<path> ./scripts/deploy-bridge.sh   # Use pre-compiled bytecode (e.g. verified-artifacts/VeeraMintBurnOFTAdapter.json)
#   ./scripts/deploy-bridge.sh <url> --keystore <path>       # Use a keystore
#   ./scripts/deploy-bridge.sh <url> --private-key <key>     # Use a private key
#   ./scripts/deploy-bridge.sh <url> --ledger                # Use Ledger hardware wallet
#   ./scripts/deploy-bridge.sh <url> --trezor                # Use Trezor hardware wallet

set -euo pipefail

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="${SCRIPT_PATH}/.."
ENV_FILE="${REPO_ROOT}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "${DEPLOYER_ADDRESS:-}" ]; then
  MANIFEST_PATH="${REPO_ROOT}/${DEPLOY_MANIFEST_PATH}"
  if [[ -f "$MANIFEST_PATH" ]]; then
    if command -v jq >/dev/null 2>&1; then
      DEPLOYER_ADDRESS=$(jq -r '.bootstrapAdmin' "$MANIFEST_PATH")
    elif command -v node >/dev/null 2>&1; then
      DEPLOYER_ADDRESS=$(node -e "console.log(require('$MANIFEST_PATH').bootstrapAdmin)")
    else
      DEPLOYER_ADDRESS=$(grep -m 1 '"bootstrapAdmin"' "$MANIFEST_PATH" | sed -E 's/.*"bootstrapAdmin"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    fi
    export DEPLOYER_ADDRESS
    echo "ℹ️  Loaded DEPLOYER_ADDRESS from manifest bootstrapAdmin: $DEPLOYER_ADDRESS"
  else
    echo "⚠️  Warning: Manifest file not found at $MANIFEST_PATH"
  fi
fi


RPC_URL="$1"
if [ -z "$RPC_URL" ]; then
    echo "❌ Error: RPC_URL is required"
    exit 1
fi

if ! command -v forge >/dev/null 2>&1; then
  echo "❌ Error: forge is not installed. Install Foundry before running this script." >&2
  exit 1
fi

# Determine signing options
SIGNER_FLAGS=""
if [[ "$*" == *"--keystore"* ]]; then
  # Passthrough keystore args
  SIGNER_FLAGS="$*"
elif [[ "$*" == *"--private-key"* ]]; then
  SIGNER_FLAGS="$*"
elif [[ "$*" == *"--ledger"* ]] || [[ "$*" == *"--trezor"* ]]; then
  SIGNER_FLAGS="$*"
  if [ -n "${DEPLOYER_ADDRESS:-}" ]; then
    SIGNER_FLAGS="${SIGNER_FLAGS} --sender ${DEPLOYER_ADDRESS}"
  fi
elif [ -n "${DEPLOYER_PRIVATE_KEY:-}" ]; then
  SIGNER_FLAGS="--private-key ${DEPLOYER_PRIVATE_KEY}"
elif [ -n "${HARDWARE:-}" ]; then
  SIGNER_FLAGS="${HARDWARE}"
  if [ -n "${DEPLOYER_ADDRESS:-}" ]; then
    SIGNER_FLAGS="${SIGNER_FLAGS} --sender ${DEPLOYER_ADDRESS}"
  fi
else
  # Default to dry-run or user interaction if no signer is configured
  echo "⚠️  No signer specified. Defaulting to dry-run/simulation."
  DRY_RUN=true
fi

# Dry run / broadcast settings
BROADCAST_FLAG="--broadcast"
if [ "${DRY_RUN:-false}" = "true" ]; then
  BROADCAST_FLAG=""
  echo "🛡️  DRY RUN MODE ACTIVE - simulation only, no txs will be sent."
fi

# Verification flags
VERIFY_FLAGS=""
if [ -n "${ETHERSCAN_API_KEY:-}" ] && [ "${DRY_RUN:-false}" != "true" ]; then
  VERIFY_FLAGS="--verify --etherscan-api-key ${ETHERSCAN_API_KEY}"
fi

# Execute deployment script
echo "🚀 Deploying VeeraMintBurnOFTAdapter..."
echo "🔗 RPC URL: $RPC_URL"

forge script "${REPO_ROOT}/script/DeployOFTAdapter.s.sol" \
  --rpc-url "$RPC_URL" \
  ${BROADCAST_FLAG} \
  ${VERIFY_FLAGS} \
  ${SIGNER_FLAGS}

echo "✅ Bridge deployment script complete."
