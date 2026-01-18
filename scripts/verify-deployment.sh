#!/usr/bin/env bash

# Post-Deployment Verification Script
# This script verifies that the Veera token was deployed correctly

set -e

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ENV_FILE="${SCRIPT_PATH}/../.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "$1" ]; then
    echo -e "${RED}${BOLD}❌ Error: Contract address required${NC}"
    echo -e "${YELLOW}Usage: $0 <CONTRACT_ADDRESS> [EXPECTED_ADMIN_ADDRESS]${NC}"
    exit 1
fi

CONTRACT_ADDRESS="$1"
EXPECTED_ADMIN="${2:-}"

ALL_VALIDATIONS_PASSED=true

if [ -z "$BASE_RPC_URL" ]; then
    echo -e "${RED}${BOLD}❌ Error: No RPC URL set. Check your .env file BASE_RPC_URL value.${NC}"
    exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo -e "${RED}${BOLD}cast not found. Install Foundry before running this script.${NC}" >&2
  exit 1
fi

# Print cool header
echo ""
echo -e "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║"
echo "║     ██╗   ██╗███████╗███████╗██████╗  █████╗"
echo "║     ██║   ██║██╔════╝██╔════╝██╔══██╗██╔══██╗"
echo "║     ██║   ██║█████╗  █████╗  ██████╔╝███████║"
echo "║     ╚██╗ ██╔╝██╔══╝  ██╔══╝  ██╔══██╗██╔══██║"
echo "║      ╚████╔╝ ███████╗███████╗██║  ██║██║  ██║"
echo "║       ╚═══╝  ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝"
echo "║"
echo "║           🔍 DEPLOYMENT VERIFICATION PROTOCOL 🔍"
echo "║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}📡 Contract:${NC} ${MAGENTA}$CONTRACT_ADDRESS${NC}"
echo -e "${CYAN}${BOLD}🌐 RPC:${NC} ${MAGENTA}$BASE_RPC_URL${NC}"
echo ""

# Get DEFAULT_ADMIN_ROLE hash (should be 0x00)
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

# Get role hashes from the contract's public constants (most reliable method)
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}🔐 Role Hashes${NC} ${YELLOW}⏳ Querying...${NC}"
MINTER_ROLE=$(cast call "$CONTRACT_ADDRESS" "MINTER_ROLE()(bytes32)" --rpc-url "$BASE_RPC_URL")
PAUSER_ROLE=$(cast call "$CONTRACT_ADDRESS" "PAUSER_ROLE()(bytes32)" --rpc-url "$BASE_RPC_URL")

if [ -z "$MINTER_ROLE" ] || [ -z "$PAUSER_ROLE" ]; then
    echo -e "${RED}${BOLD}${BG_RED}❌ CRITICAL: Failed to retrieve role hashes${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} ${CYAN}ADMIN:${NC} ${MAGENTA}$DEFAULT_ADMIN_ROLE${NC}"
echo -e "${GREEN}✓${NC} ${CYAN}MINTER:${NC} ${MAGENTA}$MINTER_ROLE${NC}"
echo -e "${GREEN}✓${NC} ${CYAN}PAUSER:${NC} ${MAGENTA}$PAUSER_ROLE${NC}"

# Get the admin address that has DEFAULT_ADMIN_ROLE
# Note: This is a simplified check - in practice you'd need to iterate through potential admins
if [ -n "$EXPECTED_ADMIN" ]; then
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}👑 Admin Roles${NC} ${YELLOW}🎯 $EXPECTED_ADMIN${NC}"
    
    HAS_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$EXPECTED_ADMIN" --rpc-url "$BASE_RPC_URL")
    if [ "$HAS_ROLE" == "true" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}ADMIN${NC} ${GREEN}assigned${NC}"
    else
        echo -e "   ${RED}${BOLD}✗${NC} ${CYAN}ADMIN${NC} ${RED}${BOLD}NOT assigned${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi

    HAS_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$EXPECTED_ADMIN" --rpc-url "$BASE_RPC_URL")
    if [ "$HAS_ROLE" == "true" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}MINTER${NC} ${GREEN}assigned${NC}"
    else
        echo -e "   ${RED}${BOLD}✗${NC} ${CYAN}MINTER${NC} ${RED}${BOLD}NOT assigned${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi

    HAS_ROLE=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$PAUSER_ROLE" "$EXPECTED_ADMIN" --rpc-url "$BASE_RPC_URL")
    if [ "$HAS_ROLE" == "true" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}PAUSER${NC} ${GREEN}assigned${NC}"
    else
        echo -e "   ${RED}${BOLD}✗${NC} ${CYAN}PAUSER${NC} ${RED}${BOLD}NOT assigned${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi
fi


# Check token metadata
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}📊 Token Metadata${NC} ${YELLOW}⏳ Querying...${NC}"
TOKEN_NAME=$(cast call "$CONTRACT_ADDRESS" "name()(string)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
TOKEN_SYMBOL=$(cast call "$CONTRACT_ADDRESS" "symbol()(string)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
TOTAL_SUPPLY=$(cast call "$CONTRACT_ADDRESS" "totalSupply()(uint256)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)
CAP=$(cast call "$CONTRACT_ADDRESS" "cap()(uint256)" --rpc-url "$BASE_RPC_URL" | tr -d '\n\r' | xargs)

if [ "$TOKEN_NAME" == "\"Veera Token\"" ]; then
    TOKEN_NAME_STATUS="${GREEN}${BOLD}✓ VERIFIED${NC}"
    TOKEN_NAME_EXPECTED=""
else 
    TOKEN_NAME_STATUS="${RED}${BOLD}✗ FAILED${NC}"
    TOKEN_NAME_EXPECTED="${RED}(Expected: Veera Token)${NC}"
    ALL_VALIDATIONS_PASSED=false
fi

if [ "$TOKEN_SYMBOL" == "\"VEERA\"" ]; then
    TOKEN_SYMBOL_STATUS="${GREEN}${BOLD}✓ VERIFIED${NC}"
    TOKEN_SYMBOL_EXPECTED=""
else 
    TOKEN_SYMBOL_STATUS="${RED}${BOLD}✗ FAILED${NC}"
    TOKEN_SYMBOL_EXPECTED="${RED}(Expected: VEERA)${NC}"
    ALL_VALIDATIONS_PASSED=false
fi

if [ "$TOTAL_SUPPLY" == "1000000000000000000000000000 [1e27]" ]; then
    TOTAL_SUPPLY_STATUS="${GREEN}${BOLD}✓ VERIFIED${NC}"
    TOTAL_SUPPLY_EXPECTED=""
else 
    TOTAL_SUPPLY_STATUS="${RED}${BOLD}✗ FAILED${NC}"
    TOTAL_SUPPLY_EXPECTED="${RED}(Expected: 1000000000000000000000000000 [1e27])${NC}"
    ALL_VALIDATIONS_PASSED=false
fi

if [ "$CAP" == "1000000000000000000000000000 [1e27]" ]; then
    CAP_STATUS="${GREEN}${BOLD}✓ VERIFIED${NC}"
    CAP_EXPECTED=""
else 
    CAP_STATUS="${RED}${BOLD}✗ FAILED${NC}"
    CAP_EXPECTED="${RED}(Expected: 1000000000000000000000000000 [1e27])${NC}"
    ALL_VALIDATIONS_PASSED=false
fi

echo -e "   ${TOKEN_NAME_STATUS} ${CYAN}Name:${NC} ${MAGENTA}$TOKEN_NAME${NC} ${TOKEN_NAME_EXPECTED}"
echo -e "   ${TOKEN_SYMBOL_STATUS} ${CYAN}Symbol:${NC} ${MAGENTA}$TOKEN_SYMBOL${NC} ${TOKEN_SYMBOL_EXPECTED}"
echo -e "   ${TOTAL_SUPPLY_STATUS} ${CYAN}Supply:${NC} ${MAGENTA}$TOTAL_SUPPLY${NC} ${TOTAL_SUPPLY_EXPECTED}"
echo -e "   ${CAP_STATUS} ${CYAN}Cap:${NC} ${MAGENTA}$CAP${NC} ${CAP_EXPECTED}"

# Check if contract is paused (should be false initially)
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}⏸️  Pause State${NC} ${YELLOW}⏳ Checking...${NC}"
IS_PAUSED=$(cast call "$CONTRACT_ADDRESS" "paused()(bool)" --rpc-url "$BASE_RPC_URL")
if [ "$IS_PAUSED" == "true" ]; then
    echo -e "   ${RED}${BOLD}${BG_RED}⚠️  PAUSED${NC} ${YELLOW}Emergency state detected${NC}"
    ALL_VALIDATIONS_PASSED=false
else
    echo -e "   ${GREEN}${BOLD}✓${NC} ${GREEN}Active${NC} (not paused)"
fi

# Check if deployer address has any roles (should NOT for security)
if [ -n "$DEPLOYER_ADDRESS" ]; then
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}🔒 Security Check${NC} ${YELLOW}🎯 $DEPLOYER_ADDRESS${NC}"
    
    DEPLOYER_HAS_ADMIN=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN_ROLE" "$DEPLOYER_ADDRESS" --rpc-url "$BASE_RPC_URL")
    if [ "$DEPLOYER_HAS_ADMIN" == "false" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}ADMIN${NC} ${GREEN}secure${NC}"
    else
        echo -e "   ${RED}${BOLD}${BG_RED}🚨 CRITICAL${NC} ${RED}${BOLD}Deployer HAS ADMIN role!${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi

    DEPLOYER_HAS_MINTER=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$DEPLOYER_ADDRESS" --rpc-url "$BASE_RPC_URL")
    if [ "$DEPLOYER_HAS_MINTER" == "false" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}MINTER${NC} ${GREEN}secure${NC}"
    else
        echo -e "   ${RED}${BOLD}${BG_RED}🚨 CRITICAL${NC} ${RED}${BOLD}Deployer HAS MINTER role!${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi

    DEPLOYER_HAS_PAUSER=$(cast call "$CONTRACT_ADDRESS" "hasRole(bytes32,address)(bool)" "$PAUSER_ROLE" "$DEPLOYER_ADDRESS" --rpc-url "$BASE_RPC_URL")
    if [ "$DEPLOYER_HAS_PAUSER" == "false" ]; then
        echo -e "   ${GREEN}${BOLD}✓${NC} ${CYAN}PAUSER${NC} ${GREEN}secure${NC}"
    else
        echo -e "   ${RED}${BOLD}${BG_RED}🚨 CRITICAL${NC} ${RED}${BOLD}Deployer HAS PAUSER role!${NC}"
        ALL_VALIDATIONS_PASSED=false
    fi
fi

# Final summary
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$ALL_VALIDATIONS_PASSED" == "true" ]; then
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║║"
    echo "║                    ✅ ALL VALIDATIONS PASSED ✅"
    echo "║                  🎉 DEPLOYMENT VERIFIED SUCCESSFULLY 🎉"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${CYAN}${BOLD}📝 Next:${NC} ${YELLOW}1)${NC} Verify on BaseScan ${YELLOW}2)${NC} Check source verification ${YELLOW}3)${NC} Test pause/unpause"
    echo -e "   ${MAGENTA}https://basescan.org/address/$CONTRACT_ADDRESS${NC}"
else
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║"
    echo "║                    ❌ VALIDATION FAILED ❌"
    echo "║                  ⚠️  DEPLOYMENT ISSUES DETECTED ⚠️"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${RED}${BOLD}🚨 Action Required:${NC} ${RED}Review failed checks above. Do NOT proceed until resolved.${NC}"
fi
echo ""
