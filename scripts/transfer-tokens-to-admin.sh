#!/usr/bin/env bash
set -euo pipefail

# Script to transfer all tokens from deployer to current admin
# Usage: ./scripts/transfer-tokens-to-admin.sh <CONTRACT_ADDRESS> <NEW_ADMIN_ADDRESS> [RPC_URL]

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="$(cd "$SCRIPT_PATH/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# Check for cast
if ! command -v cast >/dev/null 2>&1; then
  echo -e "${RED}${BOLD}cast not found. Install Foundry before running this script.${NC}" >&2
  exit 1
fi

# Parse arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}${BOLD}❌ Error: Missing required arguments${NC}"
    echo -e "${YELLOW}Usage: $0 <CONTRACT_ADDRESS> <NEW_ADMIN_ADDRESS> [RPC_URL]${NC}"
    echo -e "${YELLOW}Example: $0 0x82bf1beEdB0334256Ae94d812BA96EF90cFFEFd4 0x4f804166F420b7d41D0AeEF94c38BEDFdc0fDdb9${NC}"
    exit 1
fi

CONTRACT_ADDRESS="$1"
NEW_ADMIN_ADDRESS="$2"
RPC_URL="${3:-${BASE_RPC_URL:-}}"

if [ -z "$RPC_URL" ]; then
    echo -e "${RED}${BOLD}❌ Error: RPC URL required. Provide as 3rd argument or set BASE_RPC_URL in .env${NC}"
    exit 1
fi

# Keystore configuration
KEYSTORE_PATH="$REPO_ROOT/keystores/testnet-deployer-1"
PASSWORD_FILE="$REPO_ROOT/keystores/pass.pass"

if [[ ! -f "$KEYSTORE_PATH" ]]; then
    echo -e "${RED}${BOLD}❌ Error: Keystore file not found at $KEYSTORE_PATH${NC}" >&2
    exit 1
fi

if [[ ! -f "$PASSWORD_FILE" ]]; then
    echo -e "${RED}${BOLD}❌ Error: Keystore password file not found at $PASSWORD_FILE${NC}" >&2
    exit 1
fi

# Get deployer address from keystore
echo -e "${CYAN}${BOLD}Deriving deployer address from keystore...${NC}"
DEPLOYER_ADDRESS=$(cast wallet address --keystore "$KEYSTORE_PATH" --password-file "$PASSWORD_FILE" 2>/dev/null || echo "")

if [ -z "$DEPLOYER_ADDRESS" ]; then
    echo -e "${RED}${BOLD}❌ Error: Could not derive address from keystore${NC}" >&2
    exit 1
fi

echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           TRANSFER TOKENS TO ADMIN SCRIPT                    ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${BLUE}Contract Address: ${MAGENTA}$CONTRACT_ADDRESS${NC}"
echo -e "${BLUE}Deployer Address: ${MAGENTA}$DEPLOYER_ADDRESS${NC}"
echo -e "${BLUE}New Admin Address: ${MAGENTA}$NEW_ADMIN_ADDRESS${NC}"
echo -e "${BLUE}RPC URL: ${MAGENTA}$RPC_URL${NC}"
echo -e "${BLUE}Signing with Keystore: ${MAGENTA}$KEYSTORE_PATH${NC}\n"

# Verify the contract exists and is accessible
echo -e "${YELLOW}Checking contract...${NC}"
TOKEN_NAME=$(cast call "$CONTRACT_ADDRESS" "name()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -z "$TOKEN_NAME" ]; then
    echo -e "${RED}${BOLD}❌ Error: Cannot connect to contract at $CONTRACT_ADDRESS${NC}"
    echo -e "${RED}   Please verify the contract address and RPC URL are correct.${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Contract verified: ${TOKEN_NAME}\n"

# Get deployer balance
echo -e "${YELLOW}Checking deployer token balance...${NC}"
DEPLOYER_BALANCE_RAW=$(cast call "$CONTRACT_ADDRESS" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL" || echo "")

if [ "$DEPLOYER_BALANCE_RAW" == "0" ] || [ -z "$DEPLOYER_BALANCE_RAW" ]; then
    echo -e "${YELLOW}⚠ Deployer has 0 token balance. Nothing to transfer.${NC}"
    exit 0
fi

# Extract just the number part (cast may return "1000 [1e3]" format)
# Remove everything after the first space or bracket
DEPLOYER_BALANCE_RAW=$(echo "$DEPLOYER_BALANCE_RAW" | sed 's/\[.*//' | sed 's/ .*//' | tr -d ' ')

# Debug: show what we got
echo -e "${CYAN}   Raw balance value: ${DEPLOYER_BALANCE_RAW}${NC}"

# Ensure balance is in hex format for cast send
# cast call should return hex by default, but handle both cases
if [[ "$DEPLOYER_BALANCE_RAW" =~ ^0x ]]; then
    DEPLOYER_BALANCE="$DEPLOYER_BALANCE_RAW"
    echo -e "${CYAN}   Balance is already in hex format${NC}"
else
    # cast call returned decimal - convert to hex
    echo -e "${CYAN}   Converting decimal balance to hex...${NC}"
    
    # Try Python first (handles large numbers well)
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_OUTPUT=$(python3 -c "print(hex(int('$DEPLOYER_BALANCE_RAW')))" 2>&1) || true
        if [[ "$PYTHON_OUTPUT" =~ ^0x ]]; then
            DEPLOYER_BALANCE="$PYTHON_OUTPUT"
            echo -e "${GREEN}   ✓ Converted using Python3${NC}"
        else
            echo -e "${YELLOW}   Python3 conversion failed: ${PYTHON_OUTPUT}${NC}"
            DEPLOYER_BALANCE=""
        fi
    else
        echo -e "${YELLOW}   Python3 not available${NC}"
    fi
    
    # Fallback: use node if available
    if [ -z "$DEPLOYER_BALANCE" ] || [[ ! "$DEPLOYER_BALANCE" =~ ^0x ]]; then
        if command -v node >/dev/null 2>&1; then
            NODE_OUTPUT=$(node -e "console.log('0x' + BigInt('$DEPLOYER_BALANCE_RAW').toString(16))" 2>&1) || true
            if [[ "$NODE_OUTPUT" =~ ^0x ]]; then
                DEPLOYER_BALANCE="$NODE_OUTPUT"
                echo -e "${GREEN}   ✓ Converted using Node.js${NC}"
            else
                echo -e "${YELLOW}   Node.js conversion failed: ${NODE_OUTPUT}${NC}"
                DEPLOYER_BALANCE=""
            fi
        fi
    fi
    
    # Final fallback: use printf (may fail for very large numbers)
    if [ -z "$DEPLOYER_BALANCE" ] || [[ ! "$DEPLOYER_BALANCE" =~ ^0x ]]; then
        PRINTF_OUTPUT=$(printf '0x%x' "$DEPLOYER_BALANCE_RAW" 2>&1 || echo "")
        if [[ "$PRINTF_OUTPUT" =~ ^0x ]]; then
            DEPLOYER_BALANCE="$PRINTF_OUTPUT"
            echo -e "${GREEN}   ✓ Converted using printf${NC}"
        else
            echo -e "${YELLOW}   printf conversion failed: ${PRINTF_OUTPUT}${NC}"
            DEPLOYER_BALANCE=""
        fi
    fi
    
    if [ -z "$DEPLOYER_BALANCE" ] || [[ ! "$DEPLOYER_BALANCE" =~ ^0x ]]; then
        echo -e "${RED}${BOLD}❌ Error: Could not convert balance to hex format${NC}"
        echo -e "${RED}   Raw balance value: ${DEPLOYER_BALANCE_RAW}${NC}"
        echo -e "${RED}   Please ensure Python3 or Node.js is available${NC}"
        exit 1
    fi
fi

# Convert balance to human-readable format (assuming 18 decimals)
DEPLOYER_BALANCE_ETH=$(cast --to-unit "$DEPLOYER_BALANCE" ether 2>/dev/null || echo "$DEPLOYER_BALANCE")
echo -e "${GREEN}✓${NC} Deployer balance: ${MAGENTA}$DEPLOYER_BALANCE_ETH${NC} tokens\n"

# Get new admin current balance
echo -e "${YELLOW}Checking new admin token balance...${NC}"
NEW_ADMIN_BALANCE=$(cast call "$CONTRACT_ADDRESS" "balanceOf(address)(uint256)" "$NEW_ADMIN_ADDRESS" --rpc-url "$RPC_URL")
NEW_ADMIN_BALANCE_ETH=$(cast --to-unit "$NEW_ADMIN_BALANCE" ether 2>/dev/null || echo "$NEW_ADMIN_BALANCE")
echo -e "${GREEN}✓${NC} New admin current balance: ${MAGENTA}$NEW_ADMIN_BALANCE_ETH${NC} tokens\n"

# Confirmation
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}${BOLD}⚠️  WARNING: This will transfer ALL tokens from deployer to new admin${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}From: ${MAGENTA}$DEPLOYER_ADDRESS${NC} (${DEPLOYER_BALANCE_ETH} tokens)"
echo -e "${CYAN}To:   ${MAGENTA}$NEW_ADMIN_ADDRESS${NC} (will receive ${DEPLOYER_BALANCE_ETH} tokens)"
echo ""
read -p "$(echo -e "${YELLOW}❓ Do you want to proceed? (y/N): ${NC}")" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 1
fi

echo -e "${BLUE}Sending transfer transaction...${NC}"
echo -e "${CYAN}Transferring ${DEPLOYER_BALANCE_ETH} tokens (${DEPLOYER_BALANCE})...${NC}"

# Execute the transfer transaction
# cast send should accept hex format for uint256
TX_OUTPUT=$(cast send "$CONTRACT_ADDRESS" \
    "transfer(address,uint256)" \
    "$NEW_ADMIN_ADDRESS" \
    "$DEPLOYER_BALANCE" \
    --rpc-url "$RPC_URL" \
    --keystore "$KEYSTORE_PATH" \
    --password-file "$PASSWORD_FILE" \
    2>&1)

# Extract transaction hash from output
TX_HASH=$(echo "$TX_OUTPUT" | grep -oE '0x[a-fA-F0-9]{64}' | head -1 || echo "")

if [ -z "$TX_HASH" ]; then
    echo -e "${RED}${BOLD}❌ Error: Transaction failed or no hash returned${NC}"
    echo -e "${RED}Output: ${TX_OUTPUT}${NC}"
    exit 1
fi

echo -e "${GREEN}Transaction sent! Hash: ${MAGENTA}$TX_HASH${NC}"
echo -e "${BLUE}Waiting for transaction to be confirmed...${NC}"

# Wait for transaction receipt
RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json)
STATUS=$(echo "$RECEIPT" | jq -r '.status')

if [ "$STATUS" == "0x1" ]; then
    echo -e "${GREEN}${BOLD}✓ Transaction confirmed successfully!${NC}"
    
    # Verify the transfer
    echo -e "${YELLOW}Verifying transfer...${NC}"
    FINAL_DEPLOYER_BALANCE=$(cast call "$CONTRACT_ADDRESS" "balanceOf(address)(uint256)" "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")
    FINAL_ADMIN_BALANCE=$(cast call "$CONTRACT_ADDRESS" "balanceOf(address)(uint256)" "$NEW_ADMIN_ADDRESS" --rpc-url "$RPC_URL")
    
    FINAL_DEPLOYER_BALANCE_ETH=$(cast --to-unit "$FINAL_DEPLOYER_BALANCE" ether 2>/dev/null || echo "$FINAL_DEPLOYER_BALANCE")
    FINAL_ADMIN_BALANCE_ETH=$(cast --to-unit "$FINAL_ADMIN_BALANCE" ether 2>/dev/null || echo "$FINAL_ADMIN_BALANCE")
    
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                    TRANSFER COMPLETE                          ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Deployer balance: ${MAGENTA}$FINAL_DEPLOYER_BALANCE_ETH${NC} tokens"
    echo -e "${CYAN}New admin balance: ${MAGENTA}$FINAL_ADMIN_BALANCE_ETH${NC} tokens"
    echo ""
    
    if [ "$FINAL_DEPLOYER_BALANCE" == "0" ]; then
        echo -e "${GREEN}${BOLD}✓ Success:${NC} All tokens transferred to ${NEW_ADMIN_ADDRESS}"
    else
        echo -e "${YELLOW}⚠ Warning:${NC} Deployer still has ${FINAL_DEPLOYER_BALANCE_ETH} tokens remaining"
    fi
else
    echo -e "${RED}${BOLD}❌ Error: Transaction failed on-chain.${NC}"
    echo -e "${RED}Receipt: ${RECEIPT}${NC}"
    exit 1
fi

