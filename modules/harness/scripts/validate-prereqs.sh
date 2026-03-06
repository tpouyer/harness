#!/bin/bash
# Validate prerequisites for harness

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $name found: $(command -v "$cmd")"
        return 0
    else
        echo -e "${RED}✗${NC} $name not found"
        if [ -n "$install_hint" ]; then
            echo "  Install: $install_hint"
        fi
        return 1
    fi
}

echo "Checking prerequisites..."
echo ""

MISSING=0

check_command "git" "Git" "https://git-scm.com/downloads" || MISSING=$((MISSING + 1))
check_command "curl" "curl" "brew install curl" || MISSING=$((MISSING + 1))
check_command "jq" "jq" "brew install jq" || MISSING=$((MISSING + 1))
check_command "make" "GNU Make" "Pre-installed on most systems" || MISSING=$((MISSING + 1))

# Check for AI agent stack
check_command "opencode" "OpenCode" "make harness/deps/opencode" || echo "  (optional: install with make harness/deps/opencode)"
check_command "bd" "Beads (bd)" "make harness/deps/beads" || echo "  (optional: install with make harness/deps/beads)"

# Check for container runtime (needed for aap-dev)
if command -v podman &> /dev/null; then
    echo -e "${GREEN}✓${NC} Podman found: $(command -v podman)"
elif command -v docker &> /dev/null; then
    echo -e "${YELLOW}!${NC} Docker found (Podman preferred): $(command -v docker)"
else
    echo -e "${YELLOW}!${NC} Container runtime not found (needed for aap-dev)"
    echo "  Install Podman: brew install podman"
fi

echo ""
if [ $MISSING -gt 0 ]; then
    echo -e "${RED}Missing $MISSING required prerequisite(s)${NC}"
    exit 1
else
    echo -e "${GREEN}All prerequisites satisfied${NC}"
fi
