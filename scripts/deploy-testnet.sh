#!/usr/bin/env bash
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
if [[ $# -gt 0 ]]; then
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

if [[ -z "${BASE_RPC_URL:-}" ]]; then
  echo "BASE_RPC_URL environment variable is required." >&2
  exit 1
fi

read -rsp "Enter password for keystore '$(basename "$KEYSTORE_PATH")': " KEYSTORE_PASSWORD
echo

PASSWORD_FILE="$(mktemp)"
trap 'rm -f "$PASSWORD_FILE"' EXIT
printf "%s" "$KEYSTORE_PASSWORD" > "$PASSWORD_FILE"
unset KEYSTORE_PASSWORD

forge script script/DeployVeera.s.sol:DeployVeera \
  --rpc-url "$BASE_RPC_URL" \
  --broadcast \
  --keystore "$KEYSTORE_PATH" \
  --password-file "$PASSWORD_FILE" \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  "$@"
