#!/bin/bash
# MCP stdio server wrapping harness Jira context tools
# Provides: jira_fetch_context, jira_detect_issue, jira_create_issue, jira_add_comment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

# Source auth setup from jira-fetch.sh functions
source_jira_env() {
    # Load config
    [ -f "$PROJECT_ROOT/.harness/config.env" ] && source "$PROJECT_ROOT/.harness/config.env"
    [ -f "$PROJECT_ROOT/.harness.local.env" ] && source "$PROJECT_ROOT/.harness.local.env"

    export HARNESS_JIRA_BASE_URL="${HARNESS_JIRA_BASE_URL:-}"
    export HARNESS_JIRA_API_TOKEN="${HARNESS_JIRA_API_TOKEN:-}"
    export HARNESS_JIRA_EMAIL="${HARNESS_JIRA_EMAIL:-}"
    export HARNESS_JIRA_AUTH_TYPE="${HARNESS_JIRA_AUTH_TYPE:-auto}"
    export HARNESS_JIRA_API_VERSION="${HARNESS_JIRA_API_VERSION:-}"
}

# Build curl auth args
build_auth_args() {
    local TOKEN="${HARNESS_JIRA_API_TOKEN}"
    TOKEN="${TOKEN#\"}" && TOKEN="${TOKEN%\"}"
    TOKEN="${TOKEN#\'}" && TOKEN="${TOKEN%\'}"

    local EMAIL="${HARNESS_JIRA_EMAIL}"
    EMAIL="${EMAIL#\"}" && EMAIL="${EMAIL%\"}"

    if [ "${HARNESS_JIRA_AUTH_TYPE:-auto}" = "bearer" ] || [ -z "$EMAIL" ]; then
        echo "-H" "Authorization: Bearer ${TOKEN}"
    else
        echo "-u" "${EMAIL}:${TOKEN}"
    fi
}

# Detect API version
detect_api_path() {
    if [ -n "${HARNESS_JIRA_API_VERSION:-}" ]; then
        echo "/rest/api/${HARNESS_JIRA_API_VERSION}"
        return
    fi
    # Default to v2 for server/DC
    echo "/rest/api/2"
}

# Send JSON-RPC response
send_response() {
    local id="$1"
    local result="$2"
    printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$result"
}

# Send JSON-RPC error
send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%d,"message":%s}}\n' "$id" "$code" "$(echo "$message" | jq -Rs .)"
}

# Send tool result
send_tool_result() {
    local id="$1"
    local text="$2"
    local is_error="${3:-false}"
    send_response "$id" "$(jq -n --arg text "$text" --argjson err "$is_error" '{content:[{type:"text",text:$text}],isError:$err}')"
}

# Tool definitions
TOOLS_LIST=$(cat <<'TOOLS_JSON'
{
  "tools": [
    {
      "name": "jira_fetch_context",
      "description": "Fetch full Jira context including custom fields, hierarchy (Story->Epic->Initiative->Outcome), acceptance criteria, and linked handbook documents",
      "inputSchema": {
        "type": "object",
        "properties": {
          "issue_key": {
            "type": "string",
            "description": "Jira issue key (e.g., AAP-65162)"
          }
        },
        "required": ["issue_key"]
      }
    },
    {
      "name": "jira_detect_issue",
      "description": "Detect Jira issue key from git branch name, recent commits, or environment variables",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "jira_create_issue",
      "description": "Create a Jira issue and optionally link it to another issue. Use for filing cross-team issues identified during audits.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "project": {
            "type": "string",
            "description": "Jira project key (e.g., AAP, SECBUGS)"
          },
          "summary": {
            "type": "string",
            "description": "Issue summary/title"
          },
          "description": {
            "type": "string",
            "description": "Issue description"
          },
          "issue_type": {
            "type": "string",
            "description": "Issue type (Task, Bug, Story)",
            "default": "Task"
          },
          "component": {
            "type": "string",
            "description": "Jira component name"
          },
          "labels": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Labels to apply"
          },
          "priority": {
            "type": "string",
            "description": "Priority (Highest, High, Medium, Low, Lowest)",
            "default": "Medium"
          },
          "link_key": {
            "type": "string",
            "description": "Issue key to link to (e.g., AAP-65178)"
          },
          "link_type": {
            "type": "string",
            "description": "Link type name (e.g., 'is caused by')",
            "default": "is caused by"
          }
        },
        "required": ["project", "summary", "description"]
      }
    },
    {
      "name": "jira_add_comment",
      "description": "Add a comment to an existing Jira issue",
      "inputSchema": {
        "type": "object",
        "properties": {
          "issue_key": {
            "type": "string",
            "description": "Jira issue key (e.g., AAP-65162)"
          },
          "comment": {
            "type": "string",
            "description": "Comment text to add"
          }
        },
        "required": ["issue_key", "comment"]
      }
    }
  ]
}
TOOLS_JSON
)

# Handle tool calls
handle_tool_call() {
    local tool_name="$1"
    local arguments="$2"
    local call_id="$3"

    source_jira_env
    local BASE_URL="$HARNESS_JIRA_BASE_URL"
    local API_PATH
    API_PATH=$(detect_api_path)

    case "$tool_name" in
        "jira_fetch_context")
            local issue_key
            issue_key=$(echo "$arguments" | jq -r '.issue_key')

            local OUTPUT
            OUTPUT=$(cd "$PROJECT_ROOT" && \
                HARNESS_JIRA_ISSUE="$issue_key" \
                "$HARNESS_DIR/scripts/jira-fetch.sh" 2>&1) || true

            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "jira_detect_issue")
            local OUTPUT
            OUTPUT=$(cd "$PROJECT_ROOT" && \
                "$HARNESS_DIR/scripts/detect-issue.sh" 2>&1) || true

            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "jira_create_issue")
            local project summary description issue_type component labels priority link_key link_type
            project=$(echo "$arguments" | jq -r '.project')
            summary=$(echo "$arguments" | jq -r '.summary')
            description=$(echo "$arguments" | jq -r '.description')
            issue_type=$(echo "$arguments" | jq -r '.issue_type // "Task"')
            component=$(echo "$arguments" | jq -r '.component // empty')
            labels=$(echo "$arguments" | jq -r '.labels // []')
            priority=$(echo "$arguments" | jq -r '.priority // "Medium"')
            link_key=$(echo "$arguments" | jq -r '.link_key // empty')
            link_type=$(echo "$arguments" | jq -r '.link_type // "is caused by"')

            # Build issue JSON
            local ISSUE_JSON
            ISSUE_JSON=$(jq -n \
                --arg proj "$project" \
                --arg sum "$summary" \
                --arg desc "$description" \
                --arg type "$issue_type" \
                --arg pri "$priority" \
                '{
                    fields: {
                        project: { key: $proj },
                        summary: $sum,
                        description: $desc,
                        issuetype: { name: $type },
                        priority: { name: $pri }
                    }
                }')

            # Add component if specified
            if [ -n "$component" ] && [ "$component" != "null" ]; then
                ISSUE_JSON=$(echo "$ISSUE_JSON" | jq \
                    --arg comp "$component" \
                    '.fields.components = [{ name: $comp }]')
            fi

            # Add labels if specified
            if [ "$(echo "$labels" | jq 'length')" -gt 0 ] 2>/dev/null; then
                ISSUE_JSON=$(echo "$ISSUE_JSON" | jq \
                    --argjson lbls "$labels" \
                    '.fields.labels = $lbls')
            fi

            # Create the issue
            local AUTH_ARGS
            AUTH_ARGS=$(build_auth_args)
            local CREATE_RESPONSE
            CREATE_RESPONSE=$(curl -s $AUTH_ARGS \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$ISSUE_JSON" \
                "${BASE_URL}${API_PATH}/issue" 2>&1)

            local NEW_KEY
            NEW_KEY=$(echo "$CREATE_RESPONSE" | jq -r '.key // empty')

            if [ -z "$NEW_KEY" ]; then
                local err_msg
                err_msg=$(echo "$CREATE_RESPONSE" | jq -r '.errors // .errorMessages // "Unknown error"')
                send_tool_result "$call_id" "Failed to create issue: $err_msg" "true"
                return
            fi

            local OUTPUT="Created: ${NEW_KEY}"

            # Link to originating issue if specified
            if [ -n "$link_key" ] && [ "$link_key" != "null" ]; then
                local LINK_JSON
                LINK_JSON=$(jq -n \
                    --arg type "$link_type" \
                    --arg inward "$NEW_KEY" \
                    --arg outward "$link_key" \
                    '{
                        type: { name: $type },
                        inwardIssue: { key: $inward },
                        outwardIssue: { key: $outward }
                    }')

                curl -s $AUTH_ARGS \
                    -H "Content-Type: application/json" \
                    -X POST \
                    -d "$LINK_JSON" \
                    "${BASE_URL}${API_PATH}/issueLink" >/dev/null 2>&1

                OUTPUT="${OUTPUT} (linked to ${link_key} via '${link_type}')"
            fi

            send_tool_result "$call_id" "$OUTPUT"
            ;;

        "jira_add_comment")
            local issue_key comment
            issue_key=$(echo "$arguments" | jq -r '.issue_key')
            comment=$(echo "$arguments" | jq -r '.comment')

            local COMMENT_JSON
            COMMENT_JSON=$(jq -n --arg body "$comment" '{ body: $body }')

            local AUTH_ARGS
            AUTH_ARGS=$(build_auth_args)
            local RESPONSE
            RESPONSE=$(curl -s $AUTH_ARGS \
                -H "Content-Type: application/json" \
                -X POST \
                -d "$COMMENT_JSON" \
                "${BASE_URL}${API_PATH}/issue/${issue_key}/comment" 2>&1)

            local comment_id
            comment_id=$(echo "$RESPONSE" | jq -r '.id // empty')
            if [ -n "$comment_id" ]; then
                send_tool_result "$call_id" "Comment added to ${issue_key} (id: ${comment_id})"
            else
                send_tool_result "$call_id" "Failed to add comment: $RESPONSE" "true"
            fi
            ;;

        *)
            send_tool_result "$call_id" "Unknown tool: $tool_name" "true"
            ;;
    esac
}

# Main MCP protocol loop
while IFS= read -r line; do
    [ -z "$line" ] && continue

    METHOD=$(echo "$line" | jq -r '.method // empty')
    ID=$(echo "$line" | jq -r '.id // "null"')
    PARAMS=$(echo "$line" | jq -r '.params // {}')

    case "$METHOD" in
        "initialize")
            send_response "$ID" '{
                "protocolVersion": "2024-11-05",
                "capabilities": { "tools": {} },
                "serverInfo": { "name": "harness-jira", "version": "1.0.0" }
            }'
            ;;

        "notifications/initialized")
            # No response needed for notifications
            ;;

        "tools/list")
            send_response "$ID" "$TOOLS_LIST"
            ;;

        "tools/call")
            TOOL_NAME=$(echo "$PARAMS" | jq -r '.name')
            ARGUMENTS=$(echo "$PARAMS" | jq -r '.arguments // {}')
            handle_tool_call "$TOOL_NAME" "$ARGUMENTS" "$ID"
            ;;

        *)
            if [ "$ID" != "null" ]; then
                send_error "$ID" -32601 "Method not found: $METHOD"
            fi
            ;;
    esac
done
