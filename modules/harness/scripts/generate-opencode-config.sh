#!/bin/bash
# Generate .opencode.json from template and project configuration
# Discovers AGENTS.md, TOOLS.md, SKILLS.md and builds contextPaths + mcpServers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
PROVIDER="${HARNESS_AI_PROVIDER:-anthropic}"
MODEL="${HARNESS_AI_MODEL:-claude-sonnet-4-6}"
MODULE_PATH="${HARNESS_MODULE_DIR}"

# Build contextPaths array from discovered files
CONTEXT_PATHS="[]"
for candidate in AGENTS.md TOOLS.md SKILLS.md CLAUDE.md CLAUDE.local.md .github/copilot-instructions.md; do
    if [ -f "$candidate" ]; then
        CONTEXT_PATHS=$(echo "$CONTEXT_PATHS" | jq --arg p "$candidate" '. + [$p]')
    else
        # Include anyway so opencode checks for it (it skips missing files)
        CONTEXT_PATHS=$(echo "$CONTEXT_PATHS" | jq --arg p "$candidate" '. + [$p]')
    fi
done

# Build MCP servers config
MCP_SERVERS=$(jq -n \
    --arg jira_cmd "${MODULE_PATH}/mcp/jira-context-server.sh" \
    --arg aap_cmd "${MODULE_PATH}/mcp/aap-dev-server.sh" \
    '{
        "harness-jira": {
            "type": "stdio",
            "command": $jira_cmd,
            "env": []
        },
        "harness-aap-dev": {
            "type": "stdio",
            "command": $aap_cmd,
            "env": []
        }
    }')

# Check if TOOLS.md defines additional MCP servers
# (future: parse TOOLS.md for custom MCP server definitions)

# Generate the config
jq -n \
    --arg provider "$PROVIDER" \
    --arg model "$MODEL" \
    --argjson contextPaths "$CONTEXT_PATHS" \
    --argjson mcpServers "$MCP_SERVERS" \
    '{
        provider: $provider,
        model: $model,
        contextPaths: $contextPaths,
        mcpServers: $mcpServers
    }'
