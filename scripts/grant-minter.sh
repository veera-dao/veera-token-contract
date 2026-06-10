#!/usr/bin/env bash
set -euo pipefail

# Script to grant MINTER_ROLE to an address
# Usage: ./scripts/grant-minter.sh <CONTRACT_ADDRESS> <MINTER_ADDRESS> [RPC_URL]

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "${YELLOW}Usage: $0 <CONTRACT_ADDRESS> <MINTER_ADDRESS> [RPC_URL]${NC}"
    echo -e "${YELLOW}Example: $0 0x82bf1beEdB0334256Ae94d812BA96EF90cFFEFd4 0x4f804166F420b7d41D0AeEF94c38BEDFdc0fDdb9${NC}"
    exit 1
fi

CONTRACT_ADDRESS="$1"
MINTER_ADDRESS="$2"
RPC_URL="${3:-${BASE_RPC_URL:-}}"
if [ -z "$RPC_URL" ]; then
    echo -e "${RED}${BOLD}❌ Error: RPC URL required. Provide as 3rd argument or set BASE_RPC_URL in .env${NC}"
    exit 1
fi

# Determine signing method
SIGNER_FLAGS=""
SIGNER_INFO=""

if [ -n "${HARDWARE:-}" ]; then
    SIGNER_INFO="Hardware ($HARDWARE)"
    SIGNER_FLAGS="$HARDWARE"
elif [ -n "${LZ_CONFIG_PRIVATE_KEY:-}" ]; then
    SIGNER_INFO="Private Key (LZ_CONFIG_PRIVATE_KEY)"
    SIGNER_FLAGS="--private-key $LZ_CONFIG_PRIVATE_KEY"
else
    KEYSTORE_PATH="${4:-${KEYSTORE_PATH:-}}"
    PASSWORD_FILE="${5:-${PASSWORD_FILE:-}}"

    if [ -z "$KEYSTORE_PATH" ] || [ -z "$PASSWORD_FILE" ]; then
        echo -e "${RED}${BOLD}❌ Error: No signing method found.${NC}"
        echo -e "${RED}Please define HARDWARE, LZ_CONFIG_PRIVATE_KEY, or both KEYSTORE_PATH and PASSWORD_FILE.${NC}"
        exit 1
    fi

    if [[ ! -f "$KEYSTORE_PATH" ]]; then
        echo -e "${RED}${BOLD}❌ Error: Keystore not found: $KEYSTORE_PATH${NC}"
        exit 1
    fi

    if [[ ! -f "$PASSWORD_FILE" ]]; then
        echo -e "${RED}${BOLD}❌ Error: Password file not found: $PASSWORD_FILE${NC}"
        exit 1
    fi

    SIGNER_INFO="Keystore ($(basename "$KEYSTORE_PATH"))"
    SIGNER_FLAGS="--keystore $KEYSTORE_PATH --password-file $PASSWORD_FILE"
fi

# Get MINTER_ROLE hash from contract
MINTER_ROLE=$(cast call "$CONTRACT_ADDRESS" "MINTER_ROLE()(bytes32)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")

if [ -z "$MINTER_ROLE" ]; then
    echo -e "${RED}${BOLD}❌ Error: Cannot retrieve MINTER_ROLE from contract${NC}"
    echo -e "${RED}   Please verify the contract address and RPC URL are correct.${NC}"
    exit 1
fi

# Print header
echo ""
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║"
echo "║              🔐 GRANT MINTER ROLE 🔐"
echo "║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}📡 Contract:${NC} ${CONTRACT_ADDRESS}"
echo -e "${CYAN}${BOLD}🪙 New Minter:${NC} ${MINTER_ADDRESS}"
echo -e "${CYAN}${BOLD}🌐 RPC:${NC} ${RPC_URL}"
echo -e "${CYAN}${BOLD}🔑 Signer:${NC} ${SIGNER_INFO}"
echo -e "${CYAN}${BOLD}🔐 Role Hash:${NC} ${MINTER_ROLE}"
echo ""

# Verify the contract exists and is accessible
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}🔍 Verifying contract...${NC} ${YELLOW}⏳${NC}"

TOKEN_NAME=$(cast call "$CONTRACT_ADDRESS" "name()(string)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
if [ -z "$TOKEN_NAME" ]; then
    echo -e "${RED}${BOLD}❌ Error: Cannot connect to contract at $CONTRACT_ADDRESS${NC}"
    echo -e "${RED}   Please verify the contract address and RPC URL are correct.${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Contract verified: ${TOKEN_NAME}"
echo ""

# Check if minter already has the role
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}🔍 Checking current role status...${NC} ${YELLOW}⏳${NC}"

HAS_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$MINTER_ADDRESS" --rpc-url "$RPC_URL")

if [ "$HAS_ROLE" == "true" ]; then
    echo -e "${YELLOW}⚠️  Warning: ${MINTER_ADDRESS} already has MINTER_ROLE${NC}"
    echo -e "${YELLOW}   Skipping grant operation.${NC}"
    exit 0
else
    echo -e "${GREEN}✓${NC} Address does not have MINTER_ROLE (proceeding with grant)"
fi
echo ""

# Confirm before proceeding
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}${BOLD}⚠️  WARNING: This will grant MINTER_ROLE to:${NC}"
echo -e "${YELLOW}   ${MINTER_ADDRESS}${NC}"
echo -e "${YELLOW}   This address will be able to mint new tokens.${NC}"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${RED}Operation cancelled.${NC}"
    exit 1
fi

# Execute the grantRole transaction
echo ""
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}📤 Sending transaction...${NC} ${YELLOW}⏳${NC}"
echo ""

TX_HASH=$(cast send "$CONTRACT_ADDRESS" \
    "grantRole(bytes32,address)" \
    "$MINTER_ROLE" \
    "$MINTER_ADDRESS" \
    --rpc-url "$RPC_URL" \
    ${SIGNER_FLAGS} \
    --json 2>/dev/null | jq -r '.transactionHash' || echo "")

if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
    echo -e "${RED}${BOLD}❌ Error: Transaction failed${NC}"
    echo -e "${RED}   Please check your signer credentials/connection and that the signer has DEFAULT_ADMIN_ROLE.${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Transaction sent!"
echo -e "${CYAN}   TX Hash: ${TX_HASH}${NC}"
echo ""

# Wait for transaction confirmation
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}⏳ Waiting for confirmation...${NC}"

cast receipt "$TX_HASH" --rpc-url "$RPC_URL" > /dev/null 2>&1
TX_STATUS=$?

if [ $TX_STATUS -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Transaction confirmed!"
else
    echo -e "${YELLOW}⚠️  Could not verify transaction confirmation. Check manually:${NC}"
    echo -e "${CYAN}   TX Hash: ${TX_HASH}${NC}"
fi
echo ""

# Verify the role was granted
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}🔍 Verifying role grant...${NC} ${YELLOW}⏳${NC}"

# Wait a moment for state to update
sleep 2

HAS_ROLE_AFTER=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$MINTER_ADDRESS" --rpc-url "$RPC_URL")

if [ "$HAS_ROLE_AFTER" == "true" ]; then
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║"
    echo "║                    ✅ MINTER ROLE GRANTED SUCCESSFULLY ✅"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${GREEN}✓${NC} ${MINTER_ADDRESS} now has MINTER_ROLE"
    echo ""
    echo -e "${CYAN}${BOLD}📝 Next Steps:${NC}"
    echo -e "${YELLOW}   1)${NC} Verify on block explorer"
    echo -e "${YELLOW}   2)${NC} Test minting functionality"
else
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║"
    echo "║                    ❌ VERIFICATION FAILED ❌"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${RED}⚠️  Transaction was sent but role verification failed.${NC}"
    echo -e "${RED}   Please check the transaction manually: ${TX_HASH}${NC}"
    exit 1
fi

echo ""

