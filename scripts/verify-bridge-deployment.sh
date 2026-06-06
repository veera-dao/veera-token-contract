#!/usr/bin/env bash

# Bridge Deployment Verification Script
# This script verifies that the LayerZero bridge adapters are deployed and configured correctly
# according to the LayerZero V2 Integration Checklist.
#
# Usage:
#   ./scripts/verify-bridge-deployment.sh testnet
#   ./scripts/verify-bridge-deployment.sh mainnet

set -euo pipefail

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

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="${SCRIPT_PATH}/.."
ENV_FILE="${REPO_ROOT}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

if [ -z "${1:-}" ]; then
    echo -e "${RED}${BOLD}❌ Error: Environment argument required (mainnet or testnet)${NC}"
    echo -e "${YELLOW}Usage: $0 <mainnet|testnet>${NC}"
    exit 1
fi

ENV="$1"
if [ "$ENV" != "mainnet" ] && [ "$ENV" != "testnet" ] && [ "$ENV" != "local" ]; then
    echo -e "${RED}${BOLD}❌ Error: Invalid environment '$ENV'${NC}"
    echo -e "${YELLOW}Must be 'mainnet' or 'testnet' or 'local'${NC}"
    exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
  echo -e "${RED}${BOLD}cast not found. Install Foundry before running this script.${NC}" >&2
  exit 1
fi

# Cool header
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
echo "║             🌉 BRIDGE INTEGRATION PROTOCOL 🌉"
echo "║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Read manifest helper using node
read_manifest_val() {
  node -e "
    const fs = require('fs');
    const path = require('path');
    const envPath = process.env.DEPLOY_MANIFEST_PATH;
    const manifestFile = envPath || 'deploy_manifest.testnet.json';
    const manifestPath = path.isAbsolute(manifestFile)
      ? manifestFile
      : path.resolve('${REPO_ROOT}', manifestFile);
    if (!fs.existsSync(manifestPath)) {
      console.error('Error: deploy manifest not found at ' + manifestPath);
      process.exit(1);
    }
    const data = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const keyPath = '$1'.split('.');
    let val = data;
    for (const key of keyPath) {
      if (key === '') continue;
      val = val[key];
    }
    console.log(val || '');
  "
}

# Define chain arrays based on environment
if [ "$ENV" == "mainnet" ]; then
    CHAINS=("8453" "56")
    CHAIN_NAMES=("Base Mainnet" "BSC Mainnet")
    # Fallback public RPCs
    DEFAULT_RPCS=(
      "https://mainnet.base.org"
      "https://bsc-dataseed.binance.org"
    )
else
    CHAINS=("84532" "97")
    CHAIN_NAMES=("Base Testnet (Sepolia)" "BSC Testnet")
    DEFAULT_RPCS=(
      "https://sepolia.base.org"
      "https://data-seed-prebsc-1-s1.binance.org:8545"
    )
fi

ALL_SYSTEMS_PASSED=true

# Pad address to bytes32 helper
to_bytes32() {
  local addr="$1"
  # Strip 0x and pad to 64 chars
  local stripped="${addr#0x}"
  printf "0x%064s" "$stripped" | tr ' ' '0'
}

to_lowercase() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

for i in "${!CHAINS[@]}"; do
    CHAIN_ID="${CHAINS[$i]}"
    CHAIN_NAME="${CHAIN_NAMES[$i]}"
    DEFAULT_RPC="${DEFAULT_RPCS[$i]}"
    
    echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}🌐 Network: $CHAIN_NAME (Chain ID: $CHAIN_ID)${NC}"
    
    # Determine RPC URL from .env
    RPC_URL=""
    if [ "$CHAIN_ID" == "8453" ]; then
        RPC_URL="${BASE_RPC_URL:-}"
    elif [ "$CHAIN_ID" == "56" ]; then
        RPC_URL="${BSC_RPC_URL:-}"
    elif [ "$CHAIN_ID" == "84532" ]; then
        RPC_URL="${BASE_SEPOLIA_RPC_URL:-}"
    elif [ "$CHAIN_ID" == "97" ]; then
        RPC_URL="${BSC_TESTNET_RPC_URL:-}"
    fi

    # Fallback to RPC_URL_XXXX if defined
    if [ -z "$RPC_URL" ]; then
        RPC_VAR="RPC_URL_${CHAIN_ID}"
        RPC_URL="${!RPC_VAR:-}"
    fi
    
    if [ -z "$RPC_URL" ]; then
        echo -e "${YELLOW}⚠️  No RPC URL configured for Chain $CHAIN_ID in .env, falling back to public RPC:${NC}"
        RPC_URL="$DEFAULT_RPC"
    fi
    
    echo -e "${CYAN}📡 RPC URL:${NC} ${MAGENTA}$RPC_URL${NC}"
    
    # Load manifest details
    EXPECTED_TOKEN=$(read_manifest_val "expectedTokenAddress")
    EXPECTED_BRIDGE=$(read_manifest_val "networks.${CHAIN_ID}.expectedBridgeAddress")
    EXPECTED_ADMIN=$(read_manifest_val "networks.${CHAIN_ID}.targetAdmin")
    EXPECTED_ENDPOINT=$(read_manifest_val "networks.${CHAIN_ID}.lzEndpoint")
    EXPECTED_EID=$(read_manifest_val "networks.${CHAIN_ID}.lzEid")
    
    echo -e "${CYAN}🌉 Deployed Bridge Address:${NC} ${MAGENTA}$EXPECTED_BRIDGE${NC}"
    
    # 1. Contract existence and code size
    CODE_SIZE=$(cast code "$EXPECTED_BRIDGE" --rpc-url "$RPC_URL" | wc -c | xargs)
    if [ "$CODE_SIZE" -le 3 ]; then
        echo -e "   ${RED}${BOLD}✗ Contract not deployed or empty${NC}"
        ALL_SYSTEMS_PASSED=false
        continue
    else
        echo -e "   ${GREEN}✓${NC} Contract code verified (Size: $CODE_SIZE bytes)"
    fi
    
    # 2. Verify token address configuration
    ACTUAL_TOKEN=$(cast call "$EXPECTED_BRIDGE" "token()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$(to_lowercase "$ACTUAL_TOKEN")" == "$(to_lowercase "$EXPECTED_TOKEN")" ]; then
        echo -e "   ${GREEN}✓${NC} Underlying Token matches manifest: ${MAGENTA}$ACTUAL_TOKEN${NC}"
    else
        echo -e "   ${RED}${BOLD}✗ Token mismatch! Found $ACTUAL_TOKEN, expected $EXPECTED_TOKEN${NC}"
        ALL_SYSTEMS_PASSED=false
    fi
    
    # 3. Verify LayerZero endpoint address configuration
    ACTUAL_ENDPOINT=$(cast call "$EXPECTED_BRIDGE" "endpoint()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$(to_lowercase "$ACTUAL_ENDPOINT")" == "$(to_lowercase "$EXPECTED_ENDPOINT")" ]; then
        echo -e "   ${GREEN}✓${NC} LayerZero Endpoint matches manifest: ${MAGENTA}$ACTUAL_ENDPOINT${NC}"
    else
        echo -e "   ${RED}${BOLD}✗ Endpoint mismatch! Found $ACTUAL_ENDPOINT, expected $EXPECTED_ENDPOINT${NC}"
        ALL_SYSTEMS_PASSED=false
    fi
    
    # 4. Verify owner / delegate configuration
    ACTUAL_OWNER=$(cast call "$EXPECTED_BRIDGE" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$(to_lowercase "$ACTUAL_OWNER")" == "$(to_lowercase "$EXPECTED_ADMIN")" ]; then
        echo -e "   ${GREEN}✓${NC} Bridge Owner matches Gnosis Safe targetAdmin: ${MAGENTA}$ACTUAL_OWNER${NC}"
    else
        echo -e "   ${RED}${BOLD}✗ Owner mismatch! Found $ACTUAL_OWNER, expected Safe $EXPECTED_ADMIN${NC}"
        ALL_SYSTEMS_PASSED=false
    fi
    
    # 5. Verify endpoint delegate
    if [ -n "$ACTUAL_ENDPOINT" ] && [ "$ACTUAL_ENDPOINT" != "0x0000000000000000000000000000000000000000" ]; then
        ACTUAL_DELEGATE=$(cast call "$ACTUAL_ENDPOINT" "delegates(address)(address)" "$EXPECTED_BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        if [ "$(to_lowercase "$ACTUAL_DELEGATE")" == "$(to_lowercase "$EXPECTED_ADMIN")" ]; then
            echo -e "   ${GREEN}✓${NC} Endpoint delegate matches Safe: ${MAGENTA}$ACTUAL_DELEGATE${NC}"
        else
            echo -e "   ${RED}${BOLD}✗ Endpoint delegate NOT set to Safe! Found $ACTUAL_DELEGATE, expected $EXPECTED_ADMIN${NC}"
            ALL_SYSTEMS_PASSED=false
        fi
    fi
    
    # 6. Verify peers configuration (Integration Pathway Wiring)
    for j in "${!CHAINS[@]}"; do
        if [ "$i" == "$j" ]; then continue; fi
        REMOTE_CHAIN_ID="${CHAINS[$j]}"
        REMOTE_NAME="${CHAIN_NAMES[$j]}"
        REMOTE_EID=$(read_manifest_val "networks.${REMOTE_CHAIN_ID}.lzEid")
        REMOTE_BRIDGE=$(read_manifest_val "networks.${REMOTE_CHAIN_ID}.expectedBridgeAddress")
        
        EXPECTED_PEER_BYTES32=$(to_bytes32 "$REMOTE_BRIDGE")
        ACTUAL_PEER_BYTES32=$(cast call "$EXPECTED_BRIDGE" "peers(uint32)(bytes32)" "$REMOTE_EID" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        
        if [ "$(to_lowercase "$ACTUAL_PEER_BYTES32")" == "$(to_lowercase "$EXPECTED_PEER_BYTES32")" ]; then
            echo -e "   ${GREEN}✓${NC} Pathway wired to ${YELLOW}$REMOTE_NAME${NC} (EID: $REMOTE_EID) peer address: ${MAGENTA}$REMOTE_BRIDGE${NC}"
        else
            echo -e "   ${RED}${BOLD}✗ Pathway NOT configured to $REMOTE_NAME (EID: $REMOTE_EID)! Found $ACTUAL_PEER_BYTES32, expected $EXPECTED_PEER_BYTES32${NC}"
            ALL_SYSTEMS_PASSED=false
        fi
    done
    
    # 7. Check activation on token contract (MINTER_ROLE)
    MINTER_ROLE=$(cast call "$EXPECTED_TOKEN" "MINTER_ROLE()(bytes32)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ -n "$MINTER_ROLE" ]; then
        HAS_MINTER=$(cast call "$EXPECTED_TOKEN" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$EXPECTED_BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        if [ "$HAS_MINTER" == "true" ]; then
            echo -e "   ${GREEN}✓${NC} Bridge Adapter is ${GREEN}${BOLD}ACTIVATED${NC} (has MINTER_ROLE on token)"
        else
            echo -e "   ${YELLOW}⚠️  Bridge Adapter lacks MINTER_ROLE on token contract (Bridging inbound will revert)${NC}"
            ALL_SYSTEMS_PASSED=false
        fi
    fi
    
    # 8. Check token pause status
    IS_PAUSED=$(cast call "$EXPECTED_TOKEN" "paused()(bool)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
    if [ "$IS_PAUSED" == "true" ]; then
        echo -e "   ${YELLOW}⚠️  Underlying token is PAUSED (Bridging outbound will revert)${NC}"
    fi
    
    # 9. Verify token balance of bridge is zero
    BRIDGE_BALANCE=$(cast call "$EXPECTED_TOKEN" "balanceOf(address)(uint256)" "$EXPECTED_BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
    if [ "$BRIDGE_BALANCE" != "0" ]; then
        echo -e "   ${YELLOW}⚠️  Bridge contract holds token balance: $BRIDGE_BALANCE wei (Direct transfer error?)${NC}"
    fi
    
done

# ──────────────────────────────────────────────────────────────────────────────
# 10. Verify on-chain DVN/ULN configuration matches intended config
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}🔍 Verifying LayerZero Pathway Configuration (DVN/ULN)${NC}"

LZ_CONFIG_FILE="layerzero.config.ts"

# Run hardhat lz:oapp:config:get and check for configuration drift
CONFIG_OUTPUT=$(cd "$REPO_ROOT" && npx hardhat lz:oapp:config:get \
    --oapp-config "$LZ_CONFIG_FILE" 2>&1) || true

if echo "$CONFIG_OUTPUT" | grep -qi "error\|fail\|cannot"; then
    echo -e "   ${RED}${BOLD}✗ Failed to query on-chain LayerZero config:${NC}"
    echo "$CONFIG_OUTPUT" | head -20
    ALL_SYSTEMS_PASSED=false
else
    echo -e "   ${GREEN}✓${NC} On-chain LayerZero pathway configuration queried successfully"
    # Output summary for manual inspection
    echo -e "   ${CYAN}📋 Configuration output (review for correctness):${NC}"
    echo "$CONFIG_OUTPUT" | head -40
fi

# 11. Display expected DVN addresses (mainnet only)
if [ "$ENV" == "mainnet" ]; then
    EXPECTED_LZ_DVN="0x9e059a54699a285714207b43B055483E78FAac25"
    EXPECTED_GOOGLE_DVN="0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc"
    echo ""
    echo -e "   ${CYAN}🛡️  Expected Mainnet DVNs:${NC}"
    echo -e "      LayerZero Labs: ${MAGENTA}$EXPECTED_LZ_DVN${NC}"
    echo -e "      Google:         ${MAGENTA}$EXPECTED_GOOGLE_DVN${NC}"
    echo -e "   ${YELLOW}⚠️  Manually verify the above DVN addresses appear in the on-chain config output.${NC}"
fi

echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$ALL_SYSTEMS_PASSED" == "true" ]; then
    echo -e "${GREEN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║║"
    echo "║                ✅ ALL BRIDGE INTEGRATIONS VERIFIED ✅"
    echo "║                🎉 CONFIGURATION CHECKS PASSED 🎉"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
else
    echo -e "${RED}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║"
    echo "║                  ❌ CONFIGURATION DEVIATIONS DETECTED ❌"
    echo "║                ⚠️  REVIEW CONFIGURATION PROTOCOLS ABOVE ⚠️"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
fi
