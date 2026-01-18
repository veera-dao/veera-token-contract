#!/usr/bin/env bash

# Post-Deployment Verification Script
# This script verifies that the Veera token was deployed correctly

set -e

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ENV_FILE="${SCRIPT_PATH}/../.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "$1" ]; then
    echo "❌ Error: Contract address required"
    echo "Usage: $0 <CONTRACT_ADDRESS> [EXPECTED_ADMIN_ADDRESS]"
    exit 1
fi

CONTRACT_ADDRESS="$1"
EXPECTED_ADMIN="${2:-}"

if [ -z "$BASE_RPC_URL" ]; then
    echo "❌ Error: BASE_RPC_URL is not set"
    exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "cast not found. Install Foundry before running this script." >&2
  exit 1
fi

echo "🔍 Verifying Veera Token deployment..."
echo "Contract Address: $CONTRACT_ADDRESS"
echo "RPC URL: $BASE_RPC_URL"
echo ""

# Get DEFAULT_ADMIN_ROLE hash (should be 0x00)
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"
MINTER_ROLE=$(cast keccak "MINTER_ROLE()")
PAUSER_ROLE=$(cast keccak "PAUSER_ROLE()")

echo "📋 Checking roles..."

# Get the admin address that has DEFAULT_ADMIN_ROLE
# Note: This is a simplified check - in practice you'd need to iterate through potential admins
if [ -n "$EXPECTED_ADMIN" ]; then
    echo "Checking if $EXPECTED_ADMIN has DEFAULT_ADMIN_ROLE..."
    HAS_ADMIN_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$EXPECTED_ADMIN" --rpc-url "$BASE_RPC_URL")
    
    if [ "$HAS_ADMIN_ROLE" == "true" ]; then
        echo "✅ $EXPECTED_ADMIN has DEFAULT_ADMIN_ROLE"
    else
        echo "❌ $EXPECTED_ADMIN does NOT have DEFAULT_ADMIN_ROLE"
        exit 1
    fi
fi

# Check token name
echo ""
echo "📋 Checking token metadata..."
TOKEN_NAME=$(cast call "$CONTRACT_ADDRESS" "name()(string)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
TOKEN_SYMBOL=$(cast call "$CONTRACT_ADDRESS" "symbol()(string)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
TOTAL_SUPPLY=$(cast call "$CONTRACT_ADDRESS" "totalSupply()(uint256)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
CAP=$(cast call "$CONTRACT_ADDRESS" "cap()(uint256)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)

echo "Name: $TOKEN_NAME"
echo "Symbol: $TOKEN_SYMBOL"
echo "Total Supply: $TOTAL_SUPPLY"
echo "Max Supply Cap: $CAP"

if [ "$TOKEN_NAME" != "Veera Token" ]; then
    echo "⚠️  Warning: Token name mismatch"
fi

if [ "$TOKEN_SYMBOL" != "VEERA" ]; then
    echo "⚠️  Warning: Token symbol mismatch"
fi

# Check if contract is paused (should be false initially)
echo ""
echo "📋 Checking pause status..."
IS_PAUSED=$(cast call "$CONTRACT_ADDRESS" "paused()(bool)" --rpc-url "$BASE_RPC_URL")
if [ "$IS_PAUSED" == "true" ]; then
    echo "⚠️  Warning: Contract is paused"
else
    echo "✅ Contract is not paused (expected)"
fi

# Check if deployer address has admin role (should NOT)
if [ -n "$HARDWARE_WALLET_ADDRESS" ]; then
    echo ""
    echo "📋 Verifying deployer does NOT have admin role..."
    DEPLOYER_HAS_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$HARDWARE_WALLET_ADDRESS" --rpc-url "$BASE_RPC_URL")
    
    if [ "$DEPLOYER_HAS_ROLE" == "false" ]; then
        echo "✅ Deployer ($HARDWARE_WALLET_ADDRESS) does NOT have admin role (correct)"
    else
        echo "❌ CRITICAL: Deployer ($HARDWARE_WALLET_ADDRESS) has admin role (security issue!)"
        exit 1
    fi
fi

echo ""
echo "✅ Verification complete!"
echo ""
echo "📝 Next steps:"
echo "1. Verify the contract on BaseScan: https://basescan.org/address/$CONTRACT_ADDRESS"
echo "2. Confirm source code verification (green checkmark)"
echo "3. Review the 'Read Contract' tab to verify all roles"
echo "4. Test that the expected admin address can pause/unpause"