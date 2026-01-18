#!/usr/bin/env bash
set -euo pipefail

if ! command -v cast >/dev/null 2>&1; then
  echo "cast not found. Install Foundry before running this script." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="$REPO_ROOT/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

KEYSTORE_DIR="${KEYSTORE_DIR:-$REPO_ROOT/keystores}"
ACCOUNT_NAME="${1:-deployer}"

mkdir -p "$KEYSTORE_DIR"

KEYSTORE_PATH="$KEYSTORE_DIR/$ACCOUNT_NAME"
if [[ -e "$KEYSTORE_PATH" ]]; then
  echo "Error: $KEYSTORE_PATH already exists. Remove it or choose another account name." >&2
  exit 1
fi

read -rsp "Enter a password for keystore '$ACCOUNT_NAME': " PASSWORD
echo
read -rsp "Confirm the password: " PASSWORD_CONFIRM
echo

if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
  echo "Error: passwords do not match." >&2
  exit 1
fi

CAST_PASSWORD="$PASSWORD" cast wallet new "$KEYSTORE_DIR" "$ACCOUNT_NAME"
unset PASSWORD PASSWORD_CONFIRM CAST_PASSWORD

echo
echo "Keystore saved to: $KEYSTORE_PATH"
echo "Keep this file and its password safe."