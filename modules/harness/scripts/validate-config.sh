#!/bin/bash
# Validate harness configuration and credentials

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

validate_jira() {
    echo "Validating Jira credentials..."

    if [ -z "$HARNESS_JIRA_BASE_URL" ]; then
        echo -e "${RED}✗${NC} HARNESS_JIRA_BASE_URL not set"
        ERRORS=$((ERRORS + 1))
        return
    fi

    if [ -z "$HARNESS_JIRA_EMAIL" ] || [ -z "$HARNESS_JIRA_API_TOKEN" ]; then
        echo -e "${YELLOW}!${NC} Jira credentials not configured"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    # Test Jira API connection
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${HARNESS_JIRA_EMAIL}:${HARNESS_JIRA_API_TOKEN}" \
        "${HARNESS_JIRA_BASE_URL}/rest/api/3/myself" 2>/dev/null || echo "000")

    if [ "$HTTP_STATUS" = "200" ]; then
        echo -e "${GREEN}✓${NC} Jira API connection successful"
    elif [ "$HTTP_STATUS" = "401" ]; then
        echo -e "${RED}✗${NC} Jira authentication failed (401)"
        ERRORS=$((ERRORS + 1))
    elif [ "$HTTP_STATUS" = "000" ]; then
        echo -e "${YELLOW}!${NC} Could not connect to Jira (network issue)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${YELLOW}!${NC} Jira returned HTTP $HTTP_STATUS"
        WARNINGS=$((WARNINGS + 1))
    fi
}

validate_ai_provider() {
    echo "Validating AI provider ($HARNESS_AI_PROVIDER)..."

    if [ -z "$HARNESS_AI_API_KEY" ]; then
        if [ "$HARNESS_AI_PROVIDER" = "local" ]; then
            echo -e "${GREEN}✓${NC} Local provider - no API key needed"
            return
        fi
        echo -e "${YELLOW}!${NC} HARNESS_AI_API_KEY not set"
        WARNINGS=$((WARNINGS + 1))
        return
    fi

    case "$HARNESS_AI_PROVIDER" in
        claude)
            # Test Anthropic API
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "x-api-key: ${HARNESS_AI_API_KEY}" \
                -H "anthropic-version: 2023-06-01" \
                "https://api.anthropic.com/v1/messages" \
                -X POST -d '{"model":"claude-sonnet-4-5-20250514","max_tokens":1,"messages":[{"role":"user","content":"test"}]}' \
                -H "Content-Type: application/json" 2>/dev/null || echo "000")

            if [ "$HTTP_STATUS" = "200" ]; then
                echo -e "${GREEN}✓${NC} Anthropic API connection successful"
            elif [ "$HTTP_STATUS" = "401" ]; then
                echo -e "${RED}✗${NC} Anthropic API authentication failed"
                ERRORS=$((ERRORS + 1))
            else
                echo -e "${YELLOW}!${NC} Anthropic API returned HTTP $HTTP_STATUS"
                WARNINGS=$((WARNINGS + 1))
            fi
            ;;
        openai)
            HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -H "Authorization: Bearer ${HARNESS_AI_API_KEY}" \
                "https://api.openai.com/v1/models" 2>/dev/null || echo "000")

            if [ "$HTTP_STATUS" = "200" ]; then
                echo -e "${GREEN}✓${NC} OpenAI API connection successful"
            elif [ "$HTTP_STATUS" = "401" ]; then
                echo -e "${RED}✗${NC} OpenAI API authentication failed"
                ERRORS=$((ERRORS + 1))
            else
                echo -e "${YELLOW}!${NC} OpenAI API returned HTTP $HTTP_STATUS"
                WARNINGS=$((WARNINGS + 1))
            fi
            ;;
        local)
            echo -e "${GREEN}✓${NC} Local provider configured"
            ;;
        *)
            echo -e "${YELLOW}!${NC} Unknown provider: $HARNESS_AI_PROVIDER"
            WARNINGS=$((WARNINGS + 1))
            ;;
    esac
}

validate_paude() {
    echo "Validating Paude configuration..."

    if [ "$HARNESS_PAUDE_BACKEND" = "podman" ]; then
        if command -v podman &> /dev/null; then
            if podman info &> /dev/null; then
                echo -e "${GREEN}✓${NC} Podman is running"
            else
                echo -e "${YELLOW}!${NC} Podman not running (start with: podman machine start)"
                WARNINGS=$((WARNINGS + 1))
            fi
        else
            echo -e "${RED}✗${NC} Podman not found"
            ERRORS=$((ERRORS + 1))
        fi
    fi
}

# Run validations
validate_jira
validate_ai_provider
validate_paude

echo ""
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}Configuration has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}Configuration has $WARNINGS warning(s)${NC}"
else
    echo -e "${GREEN}Configuration validated successfully${NC}"
fi
