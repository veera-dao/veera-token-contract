#!/usr/bin/env bash

# Manifest Integrity Check Script
# This script computes the SHA-256 checksum of deploy_manifest.json
# and verifies it against the approved production checksum.

set -e

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
MANIFEST_FILE="${SCRIPT_PATH}/../deploy_manifest.mainnet.json"
# The approved production checksum representing the audited configuration
APPROVED_CHECKSUM="ab5afe5ba3e6c4a8c57b91a5b69ac28d1d47d5cd104ffb68583e8b741bec66f0"
echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${CYAN}${BOLD}🔒 MANIFEST INTEGRITY VERIFICATION PROTOCOL${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo -e "${RED}${BOLD}❌ Error: Manifest file not found at ${MANIFEST_FILE}${NC}"
    exit 1
fi

# Compute the SHA-256 checksum
# Handle different OS implementations of shasum/sha256sum
if command -v shasum >/dev/null 2>&1; then
    COMPUTED_CHECKSUM=$(shasum -a 256 "$MANIFEST_FILE" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
    COMPUTED_CHECKSUM=$(sha256sum "$MANIFEST_FILE" | awk '{print $1}')
else
    echo -e "${RED}${BOLD}❌ Error: Neither shasum nor sha256sum found on system.${NC}"
    exit 1
fi

echo -e "${CYAN}File:             ${NC}deploy_manifest.mainnet.json"
echo -e "${CYAN}Computed Checksum:${NC} ${COMPUTED_CHECKSUM}"
echo -e "${CYAN}Expected Checksum:${NC} ${APPROVED_CHECKSUM}"

if [ "$COMPUTED_CHECKSUM" = "$APPROVED_CHECKSUM" ]; then
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    echo -e "${GREEN}${BOLD}✅ SUCCESS: Manifest integrity checksum matches!${NC}"
    echo -e "${GREEN}The deployment configuration is authentic and approved.${NC}"
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    exit 0
else
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    echo -e "${RED}${BOLD}🚨 WARNING: Manifest integrity checksum mismatch!${NC}"
    echo -e "${YELLOW}Proposing changes to deploy_manifest.mainnet.json requires updating${NC}"
    echo -e "${YELLOW}both the code-level integrity hash in DeployVeera.s.sol and${NC}"
    echo -e "${YELLOW}the script APPROVED_CHECKSUM in scripts/verify-manifest-checksum.sh.${NC}"
    echo -e "${YELLOW}Please review the changes manually before deploying to production.${NC}"
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    exit 1
fi
