#!/usr/bin/env bash
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Resolve directories dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.local.json"

# Load environment variables
if [ -f "$SCRIPT_DIR/../.env" ]; then
    # Filter out comments and export
    export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║              🌉 VEERA TOKEN BRIDGE UTILITY 🌉                 ║${NC}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}\n"

# Verify command arguments
if [ "$#" -lt 3 ]; then
    echo -e "${RED}${BOLD}❌ Error: Missing arguments.${NC}"
    echo -e "Usage: $0 <AMOUNT_TO_BRIDGE> <RECIPIENT_ADDRESS> <PRIVATE_KEY>"
    echo -e "Example: $0 100 0xB80e7704b80F4E3a0115E06e11D9222193C71B07 \$LZ_CONFIG_PRIVATE_KEY"
    exit 1
fi

AMOUNT_DECIMAL="$1"
RECIPIENT_ADDRESS="$2"
USER_PRIVATE_KEY="$3"

# Read configurations from manifest
if [ ! -f "$MANIFEST_PATH" ]; then
    echo -e "${RED}${BOLD}❌ Error: manifest not found at $MANIFEST_PATH${NC}"
    exit 1
fi

TOKEN_ADDRESS=$(jq -r '.expectedTokenAddress' "$MANIFEST_PATH")
BASE_BRIDGE=$(jq -r '.networks["84532"].expectedBridgeAddress' "$MANIFEST_PATH")
BSC_EID=$(jq -r '.networks["97"].lzEid' "$MANIFEST_PATH")
BASE_RPC="${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}"

# Format amount to 18 decimals (wei)
AMOUNT_WEI=$(cast to-wei "$AMOUNT_DECIMAL")

# Convert recipient to bytes32 format (returns 32 bytes starting with 0x)
RECIPIENT_BYTES32=$(cast abi-encode "f(address)" "$RECIPIENT_ADDRESS")

echo -e "${BLUE}Configuration Info:${NC}"
echo -e "  - Token Address:         ${YELLOW}$TOKEN_ADDRESS${NC}"
echo -e "  - Base Bridge (Adapter): ${YELLOW}$BASE_BRIDGE${NC}"
echo -e "  - Destination Chain EID: ${YELLOW}$BSC_EID (BSC Testnet)${NC}"
echo -e "  - Amount:                ${GREEN}$AMOUNT_DECIMAL VEERA ($AMOUNT_WEI wei)${NC}"
echo -e "  - Recipient:             ${GREEN}$RECIPIENT_ADDRESS${NC}\n"

# 1. ERC20 Approve Spender
echo -e "${BLUE}🔄 Step 1: Checking and approving spender allowance on Base Sepolia...${NC}"
SENDER_ADDRESS=$(cast wallet address --private-key "$USER_PRIVATE_KEY")
CURRENT_ALLOWANCE=$(cast call "$TOKEN_ADDRESS" "allowance(address,address)(uint256)" "$SENDER_ADDRESS" "$BASE_BRIDGE" --rpc-url "$BASE_RPC")

# BigInt comparison using Node since bash does not support 256-bit integers
if node -e "process.exit(BigInt('$CURRENT_ALLOWANCE') < BigInt('$AMOUNT_WEI') ? 0 : 1)"; then
    echo -e "  Current allowance is ${YELLOW}$CURRENT_ALLOWANCE${NC}. Approving ${GREEN}$AMOUNT_WEI${NC}..."
    APPROVE_TX=$(cast send "$TOKEN_ADDRESS" "approve(address,uint256)" "$BASE_BRIDGE" "$AMOUNT_WEI" --rpc-url "$BASE_RPC" --private-key "$USER_PRIVATE_KEY" --json 2>/dev/null | jq -r '.transactionHash' || echo "")
    if [ -n "$APPROVE_TX" ] && [ "$APPROVE_TX" != "null" ]; then
        echo -e "  ${GREEN}✓ Token approved successfully! TX: $APPROVE_TX${NC}"
    else
        echo -e "  ${RED}❌ Token approval failed.${NC}"
        exit 1
    fi
else
    echo -e "  ${GREEN}✓ Sufficient allowance already granted ($CURRENT_ALLOWANCE). Skipping approval.${NC}"
fi

# 2. Dynamic LayerZero Fee Quote
echo -e "\n${BLUE}🔄 Step 2: Querying LayerZero cross-chain gas fee quote...${NC}"
# Extra Options: 200,000 gas, 0 native value. Bytes format: 0x00030100110100000000000000000000000000030d40
EXTRA_OPTIONS="0x00030100110100000000000000000000000000030d40"

# Struct params: (uint32 dstEid, bytes32 to, uint256 amountLD, uint256 minAmountLD, bytes extraOptions, bytes composeMsg, bytes oftCmd)
# Enclosing params inside cast call format:
QUOTE_OUT=$(cast call "$BASE_BRIDGE" \
    "quoteSend((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),bool)((uint256,uint256))" \
    "($BSC_EID,$RECIPIENT_BYTES32,$AMOUNT_WEI,$AMOUNT_WEI,$EXTRA_OPTIONS,0x,0x)" \
    "false" \
    --rpc-url "$BASE_RPC" || echo "")

if [ -z "$QUOTE_OUT" ]; then
    echo -e "${RED}❌ Error: Failed to fetch fee quote from bridge.${NC}"
    exit 1
fi

# Extract native fee
NATIVE_FEE=$(echo "$QUOTE_OUT" | tr -d '()' | awk -F',' '{print $1}' | awk '{print $1}')
echo -e "  Quoted Native Fee: ${GREEN}$(cast to-unit "$NATIVE_FEE" ether) ETH ($NATIVE_FEE wei)${NC}"

# 3. Execute Send
echo -e "\n${BLUE}🔄 Step 3: Sending bridging transaction...${NC}"
SEND_TX=$(cast send "$BASE_BRIDGE" \
    "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)(uint256,uint256)" \
    "($BSC_EID,$RECIPIENT_BYTES32,$AMOUNT_WEI,$AMOUNT_WEI,$EXTRA_OPTIONS,0x,0x)" \
    "($NATIVE_FEE,0)" \
    "$SENDER_ADDRESS" \
    --value "$NATIVE_FEE" \
    --rpc-url "$BASE_RPC" \
    --private-key "$USER_PRIVATE_KEY" \
    --json 2>/dev/null | jq -r '.transactionHash' || echo "")

if [ -n "$SEND_TX" ] && [ "$SEND_TX" != "null" ]; then
    echo -e "\n${GREEN}${BOLD}🎉 SUCCESS! Bridge Transaction Sent Successfully!${NC}"
    echo -e "  - Transaction Hash: ${CYAN}$SEND_TX${NC}"
    echo -e "  - Track status here: ${CYAN}https://testnet.layerzeroscan.com/tx/$SEND_TX${NC}"
else
    echo -e "\n${RED}${BOLD}❌ Error: Bridge transaction failed.${NC}"
    exit 1
fi
