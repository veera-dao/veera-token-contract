#!/usr/bin/env bash

# Testnet Deployment Script (CREATE2 Deterministic Deployment)
# Deploys VeeraToken via CREATE2 using a keystore-based signer.
#
# The keystore MUST contain the private key of the Bootstrap Admin EOA
# defined in deploy_manifest.json. The derived address will be used as --sender
# and must match the manifest's bootstrapAdmin.
#
# See README.md Section 2 for the full deterministic deployment workflow.
#
# Usage:
#   ./scripts/deploy-testnet.sh                              # Uses default keystore
#   ./scripts/deploy-testnet.sh path/to/keystore             # Custom keystore
#   ./scripts/deploy-testnet.sh path/to/keystore --verify    # With contract verification
#   DRY_RUN=true ./scripts/deploy-testnet.sh                 # Simulate without broadcasting

set -euo pipefail

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Install Foundry before running this script." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$REPO_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

DEFAULT_KEYSTORE="$REPO_ROOT/keystores/deployer"
if [[ $# -gt 0 && "$1" != --* ]]; then
  KEYSTORE_PATH="$1"
  shift
else
  KEYSTORE_PATH="$DEFAULT_KEYSTORE"
fi

if [[ "$KEYSTORE_PATH" != /* ]]; then
  KEYSTORE_PATH="$REPO_ROOT/$KEYSTORE_PATH"
fi

if [[ ! -f "$KEYSTORE_PATH" ]]; then
  echo "Keystore file not found: $KEYSTORE_PATH" >&2
  echo "Generate one with scripts/generate-testnet-keystore.sh first." >&2
  exit 1
fi

# Support both RPC_URL (generic) and BASE_RPC_URL (legacy) env vars
RPC_URL="${RPC_URL:-${BASE_RPC_URL:-}}"

if [[ -z "$RPC_URL" ]]; then
  echo "RPC_URL (or BASE_RPC_URL) environment variable is required." >&2
  exit 1
fi

# Run manifest integrity check before deploying
echo "🔒 Running manifest integrity check..."
bash "$REPO_ROOT/scripts/verify-manifest-checksum.sh"
echo ""

read -rsp "Enter password for keystore '$(basename "$KEYSTORE_PATH")': " KEYSTORE_PASSWORD
echo

PASSWORD_FILE="$(mktemp)"
trap 'rm -f "$PASSWORD_FILE"' EXIT
printf "%s" "$KEYSTORE_PASSWORD" > "$PASSWORD_FILE"
unset KEYSTORE_PASSWORD

VERIFY_FLAGS=""
if [[ -n "${ETHERSCAN_API_KEY:-}" ]]; then
  VERIFY_FLAGS="--verify --etherscan-api-key $ETHERSCAN_API_KEY"
fi

forge script script/DeployVeera.s.sol:DeployVeera \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --keystore "$KEYSTORE_PATH" \
  --password-file "$PASSWORD_FILE" \
  $VERIFY_FLAGS \
  "$@"
