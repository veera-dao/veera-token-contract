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
  echo "Generate one with scripts/generate-keystore.sh first." >&2
  exit 1
fi

if [[ -z "${RPC_URL:-}" ]]; then
  echo "RPC_URL environment variable is required." >&2
  exit 1
fi

for required in TOKEN_NAME TOKEN_SYMBOL TOKEN_OWNER TOKEN_INITIAL_SUPPLY; do
  if [[ -z "${!required:-}" ]]; then
    echo "$required environment variable is required." >&2
    exit 1
  fi
done

read -rsp "Enter password for keystore '$(basename "$KEYSTORE_PATH")': " KEYSTORE_PASSWORD
echo

PASSWORD_FILE="$(mktemp)"
trap 'rm -f "$PASSWORD_FILE"' EXIT
printf "%s" "$KEYSTORE_PASSWORD" > "$PASSWORD_FILE"
unset KEYSTORE_PASSWORD

forge script script/DeployBaseERC20.s.sol:DeployBaseERC20 \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --keystore "$KEYSTORE_PATH" \
  --password-file "$PASSWORD_FILE" \
  "$@"
