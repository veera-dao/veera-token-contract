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
    echo -e "Usage: $0 <AMOUNT_TO_BRIDGE> <RECIPIENT_ADDRESS> <PRIVATE_KEY|--hardware|--hardware:ledger|--hardware:trezor> [RPC_URL]"
    echo -e "Example (Private Key):      $0 100 0xB80e7704b80F4E3a0115E06e11D9222193C71B07 \$LZ_CONFIG_PRIVATE_KEY"
    echo -e "Example (Hardware Ledger):  $0 100 0xB80e7704b80F4E3a0115E06e11D9222193C71B07 --hardware:ledger https://mainnet.base.org"
    echo -e "Example (Hardware Trezor):  $0 100 0xB80e7704b80F4E3a0115E06e11D9222193C71B07 --hardware:trezor https://mainnet.base.org"
    exit 1
fi

AMOUNT_DECIMAL="$1"
RECIPIENT_ADDRESS="$2"
SIGNING_ARG="$3"
BASE_RPC=""

USE_HARDWARE=false
HW_WALLET_TYPE=""
HW_FLAG=""

if [[ "$SIGNING_ARG" == "--hardware" || "$SIGNING_ARG" == "--hardware:ledger" ]]; then
    USE_HARDWARE=true
    HW_WALLET_TYPE="Ledger"
    HW_FLAG="--ledger"
elif [[ "$SIGNING_ARG" == "--hardware:trezor" ]]; then
    USE_HARDWARE=true
    HW_WALLET_TYPE="Trezor"
    HW_FLAG="--trezor"
fi

if [ "$USE_HARDWARE" = true ]; then
    if [ "$#" -ge 4 ]; then
        BASE_RPC="$4"
    else
        BASE_RPC="${BASE_MAINNET_RPC_URL:-https://mainnet.base.org}"
    fi
else
    USE_HARDWARE=false
    USER_PRIVATE_KEY="$SIGNING_ARG"
    if [ "$#" -ge 4 ]; then
        BASE_RPC="$4"
    else
        BASE_RPC="${BASE_SEPOLIA_RPC_URL:-https://sepolia.base.org}"
    fi
fi

# Query Chain ID from RPC dynamically
echo -e "${BLUE}🔍 Querying chain ID from RPC...${NC}"
CHAIN_ID=$(cast chain-id --rpc-url "$BASE_RPC")
echo -e "  Chain ID: ${GREEN}$CHAIN_ID${NC}"

# Set config path and network params based on Chain ID
if [ "$CHAIN_ID" = "8453" ]; then
    MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.mainnet.json"
    SRC_NET="8453"
    DST_NET="56"
    SRC_NAME="Base Mainnet"
    DST_NAME="BSC Mainnet"
    LZ_SCAN_URL="https://layerzeroscan.com/tx"
elif [ "$CHAIN_ID" = "56" ]; then
    MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.mainnet.json"
    SRC_NET="56"
    DST_NET="8453"
    SRC_NAME="BSC Mainnet"
    DST_NAME="Base Mainnet"
    LZ_SCAN_URL="https://layerzeroscan.com/tx"
elif [ "$CHAIN_ID" = "84532" ]; then
    MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.testnet.json"
    if [ ! -f "$MANIFEST_PATH" ]; then
        MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.local.json"
    fi
    SRC_NET="84532"
    DST_NET="97"
    SRC_NAME="Base Sepolia"
    DST_NAME="BSC Testnet"
    LZ_SCAN_URL="https://testnet.layerzeroscan.com/tx"
elif [ "$CHAIN_ID" = "97" ]; then
    MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.testnet.json"
    if [ ! -f "$MANIFEST_PATH" ]; then
        MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.local.json"
    fi
    SRC_NET="97"
    DST_NET="84532"
    SRC_NAME="BSC Testnet"
    DST_NAME="Base Sepolia"
    LZ_SCAN_URL="https://testnet.layerzeroscan.com/tx"
else
    # Fallback to local manifest
    MANIFEST_PATH="$SCRIPT_DIR/../deploy_manifest.local.json"
    SRC_NET="31337"
    DST_NET="0"
    SRC_NAME="Local Testnet"
    DST_NAME="Local Testnet"
    LZ_SCAN_URL="https://testnet.layerzeroscan.com/tx"
fi

# Read configurations from manifest
if [ ! -f "$MANIFEST_PATH" ]; then
    echo -e "${RED}${BOLD}❌ Error: manifest not found at $MANIFEST_PATH${NC}"
    exit 1
fi

TOKEN_ADDRESS=$(jq -r '.expectedTokenAddress' "$MANIFEST_PATH")
BASE_BRIDGE=$(jq -r ".networks[\"$SRC_NET\"].expectedBridgeAddress" "$MANIFEST_PATH")
BSC_EID=$(jq -r ".networks[\"$DST_NET\"].lzEid" "$MANIFEST_PATH")

# Format amount to 18 decimals (wei)
AMOUNT_WEI=$(cast to-wei "$AMOUNT_DECIMAL")

# Convert recipient to bytes32 format (returns 32 bytes starting with 0x)
RECIPIENT_BYTES32=$(cast abi-encode "f(address)" "$RECIPIENT_ADDRESS")

# Get Sender/Signer Address
if [ "$USE_HARDWARE" = true ]; then
    echo -e "${BLUE}Please connect and unlock your $HW_WALLET_TYPE hardware wallet...${NC}"
    SENDER_ADDRESS=$(cast wallet address "$HW_FLAG")
else
    SENDER_ADDRESS=$(cast wallet address --private-key "$USER_PRIVATE_KEY")
fi

echo -e "\n${BLUE}Configuration Info:${NC}"
echo -e "  - Token Address:         ${YELLOW}$TOKEN_ADDRESS${NC}"
echo -e "  - Source Bridge (Adapter): ${YELLOW}$BASE_BRIDGE${NC}"
echo -e "  - Source Network:        ${GREEN}$SRC_NAME${NC}"
echo -e "  - Destination Chain EID: ${YELLOW}$BSC_EID ($DST_NAME)${NC}"
echo -e "  - Amount:                ${GREEN}$AMOUNT_DECIMAL VEERA ($AMOUNT_WEI wei)${NC}"
echo -e "  - Recipient:             ${GREEN}$RECIPIENT_ADDRESS${NC}"
echo -e "  - Sender/Signer Address: ${GREEN}$SENDER_ADDRESS${NC}"
echo -e "  - Signing Mode:          ${CYAN}$( [ "$USE_HARDWARE" = true ] && echo "Hardware Wallet ($HW_WALLET_TYPE)" || echo "Private Key" )${NC}"
echo -e "  - Source RPC:            ${YELLOW}$BASE_RPC${NC}\n"

# Acknowledge / confirmation prompt
read -p "Proceed with the bridge transaction? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]]; then
    echo -e "${RED}Transaction cancelled by user.${NC}"
    exit 0
fi

# 1. ERC20 Approve Spender
echo -e "\n${BLUE}🔄 Step 1: Checking and approving spender allowance on $SRC_NAME...${NC}"
CURRENT_ALLOWANCE=$(cast call "$TOKEN_ADDRESS" "allowance(address,address)(uint256)" "$SENDER_ADDRESS" "$BASE_BRIDGE" --rpc-url "$BASE_RPC")

# BigInt comparison using Node since bash does not support 256-bit integers
if node -e "process.exit(BigInt('$CURRENT_ALLOWANCE') < BigInt('$AMOUNT_WEI') ? 0 : 1)"; then
    echo -e "  Current allowance is ${YELLOW}$CURRENT_ALLOWANCE${NC}. Approving ${GREEN}$AMOUNT_WEI${NC}..."
    if [ "$USE_HARDWARE" = true ]; then
        echo -e "${BLUE}Please confirm the approval transaction on your $HW_WALLET_TYPE...${NC}"
        APPROVE_TX=$(cast send "$TOKEN_ADDRESS" "approve(address,uint256)" "$BASE_BRIDGE" "$AMOUNT_WEI" --rpc-url "$BASE_RPC" "$HW_FLAG" --json | jq -r '.transactionHash' || echo "")
    else
        APPROVE_TX=$(cast send "$TOKEN_ADDRESS" "approve(address,uint256)" "$BASE_BRIDGE" "$AMOUNT_WEI" --rpc-url "$BASE_RPC" --private-key "$USER_PRIVATE_KEY" --json 2>/dev/null | jq -r '.transactionHash' || echo "")
    fi
    
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
if [ "$USE_HARDWARE" = true ]; then
    echo -e "${BLUE}Please confirm the send transaction on your $HW_WALLET_TYPE...${NC}"
    SEND_TX=$(cast send "$BASE_BRIDGE" \
        "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)(uint256,uint256)" \
        "($BSC_EID,$RECIPIENT_BYTES32,$AMOUNT_WEI,$AMOUNT_WEI,$EXTRA_OPTIONS,0x,0x)" \
        "($NATIVE_FEE,0)" \
        "$SENDER_ADDRESS" \
        --value "$NATIVE_FEE" \
        --rpc-url "$BASE_RPC" \
        "$HW_FLAG" \
        --json | jq -r '.transactionHash' || echo "")
else
    SEND_TX=$(cast send "$BASE_BRIDGE" \
        "send((uint32,bytes32,uint256,uint256,bytes,bytes,bytes),(uint256,uint256),address)(uint256,uint256)" \
        "($BSC_EID,$RECIPIENT_BYTES32,$AMOUNT_WEI,$AMOUNT_WEI,$EXTRA_OPTIONS,0x,0x)" \
        "($NATIVE_FEE,0)" \
        "$SENDER_ADDRESS" \
        --value "$NATIVE_FEE" \
        --rpc-url "$BASE_RPC" \
        --private-key "$USER_PRIVATE_KEY" \
        --json 2>/dev/null | jq -r '.transactionHash' || echo "")
fi

if [ -n "$SEND_TX" ] && [ "$SEND_TX" != "null" ]; then
    echo -e "\n${GREEN}${BOLD}🎉 SUCCESS! Bridge Transaction Sent Successfully!${NC}"
    echo -e "  - Transaction Hash: ${CYAN}$SEND_TX${NC}"
    echo -e "  - Track status here: ${CYAN}$LZ_SCAN_URL/$SEND_TX${NC}"
else
    echo -e "\n${RED}${BOLD}❌ Error: Bridge transaction failed.${NC}"
    exit 1
fi
