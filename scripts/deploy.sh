#!/usr/bin/env bash

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ENV_FILE="${SCRIPT_PATH}/../.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "$BASE_RPC_URL" ]; then
    echo "❌ Error: BASE_RPC_URL is not set in .env"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "❌ Error: ETHERSCAN_API_KEY is not set in .env"
    exit 1
fi

if [ -z "$DEPLOYER_ADDRESS" ]; then
    echo "❌ Error: DEPLOYER_ADDRESS is not set in .env"
    exit 1
fi

if [ -z "$HARDWARE" ]; then
    echo "❌ Error: HARDWARE is not set in .env"
    exit 1
fi

if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found. Install Foundry before running this script." >&2
  exit 1
fi

forge script script/DeployVeera.s.sol \
  --rpc-url ${BASE_RPC_URL} \
  --sig "run()" \
  --sender ${DEPLOYER_ADDRESS} \
  --broadcast \
  --verify \
  --etherscan-api-key ${ETHERSCAN_API_KEY} \
  ${HARDWARE}