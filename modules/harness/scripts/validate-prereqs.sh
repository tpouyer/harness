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

# Check for container runtime
if command -v podman &> /dev/null; then
    echo -e "${GREEN}✓${NC} Podman found: $(command -v podman)"
elif command -v docker &> /dev/null; then
    echo -e "${YELLOW}!${NC} Docker found (Podman preferred): $(command -v docker)"
else
    echo -e "${RED}✗${NC} Container runtime not found"
    echo "  Install Podman: brew install podman"
    MISSING=$((MISSING + 1))
fi

# Check for paude
if command -v paude &> /dev/null; then
    echo -e "${GREEN}✓${NC} Paude found: $(command -v paude)"
else
    echo -e "${YELLOW}!${NC} Paude not found (optional for local testing)"
    echo "  Install: pip install paude"
fi

echo ""
if [ $MISSING -gt 0 ]; then
    echo -e "${RED}Missing $MISSING required prerequisite(s)${NC}"
    exit 1
else
    echo -e "${GREEN}All prerequisites satisfied${NC}"
fi
