#!/bin/bash
# Paude session management for harness

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"
PROMPTS_DIR="${HARNESS_PATH}/modules/harness/prompts"

ACTION="${1:-help}"
TASK_TYPE="${2:-}"
PROVIDER="${3:-${HARNESS_AI_PROVIDER:-claude}}"

# Detect issue for session naming
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "default")
SESSION_NAME="harness-${ISSUE}"

# Build allowed-domains flags (paude expects repeated --allowed-domains flags)
build_domain_flags() {
    local DOMAINS="${HARNESS_PAUDE_ALLOWED_DOMAINS:-default}"
    local FLAGS=""
    IFS=',' read -ra DOMAIN_LIST <<< "$DOMAINS"
    for domain in "${DOMAIN_LIST[@]}"; do
        FLAGS="$FLAGS --allowed-domains $domain"
    done
    echo "$FLAGS"
}

# Create a paude session if it doesn't already exist
ensure_session() {
    if paude list 2>/dev/null | grep -q "$SESSION_NAME"; then
        return 0
    fi

    echo "Creating session: $SESSION_NAME"
    local DOMAIN_FLAGS
    DOMAIN_FLAGS=$(build_domain_flags)

    # shellcheck disable=SC2086
    paude create --yolo \
        $DOMAIN_FLAGS \
        "$SESSION_NAME"
}

case "$ACTION" in
    create)
        echo "Creating paude session: $SESSION_NAME"

        if command -v paude &> /dev/null; then
            DOMAIN_FLAGS=$(build_domain_flags)

            # shellcheck disable=SC2086
            paude create --yolo \
                $DOMAIN_FLAGS \
                "$SESSION_NAME" || {
                    echo "Note: paude create failed - this may be expected if paude is not fully configured"
                }
        else
            echo "Warning: paude not installed"
            echo "Would create session: $SESSION_NAME"
        fi
        ;;

    start)
        echo "Starting session: $SESSION_NAME"
        if command -v paude &> /dev/null; then
            paude start "$SESSION_NAME" || echo "Session start skipped"
        else
            echo "Warning: paude not installed"
        fi
        ;;

    stop)
        echo "Stopping session: $SESSION_NAME"
        if command -v paude &> /dev/null; then
            paude stop "$SESSION_NAME" || echo "Session stop skipped"
        fi
        ;;

    list)
        if command -v paude &> /dev/null; then
            paude list | grep "harness-" || echo "No harness sessions found"
        else
            echo "paude not installed"
        fi
        ;;

    cleanup)
        echo "Cleaning up harness sessions..."
        if command -v paude &> /dev/null; then
            paude list 2>/dev/null | grep "harness-" | while read -r session; do
                paude stop "$session" 2>/dev/null || true
                paude delete "$session" --confirm 2>/dev/null || true
            done
        fi
        ;;

    run)
        # Run a task in the agent container
        if [ -z "$TASK_TYPE" ]; then
            echo "Error: Task type required" >&2
            echo "Usage: paude-session.sh run <task-type> [provider]" >&2
            exit 1
        fi

        echo "Running task: $TASK_TYPE with provider: $PROVIDER"

        # Render the prompt
        "$SCRIPT_DIR/prompt-render.sh" "$TASK_TYPE" > "$CACHE_DIR/prompt-${ISSUE}.md"

        # Create session if needed, copy prompt, and connect
        if command -v paude &> /dev/null; then
            ensure_session
            paude cp "$CACHE_DIR/prompt-${ISSUE}.md" "${SESSION_NAME}:.harness/prompt.md"
            echo "Prompt copied to session. Connecting..."
            paude start "$SESSION_NAME"
        else
            echo "Note: Running in simulation mode (paude not installed)"
            echo ""
            echo "Would send to $PROVIDER agent:"
            echo "---"
            head -50 "$CACHE_DIR/prompt-${ISSUE}.md"
            echo "---"
            echo ""

            # Create a simulated result
            jq -n \
                --arg task "$TASK_TYPE" \
                --arg provider "$PROVIDER" \
                --arg issue "$ISSUE" \
                '{
                    task: $task,
                    provider: $provider,
                    issue: $issue,
                    status: "simulated",
                    result: {
                        summary: "This is a simulated response. Install paude and configure AI credentials for real results.",
                        details: []
                    },
                    _meta: {
                        completed_at: (now | todate)
                    }
                }' > "$CACHE_DIR/result-${ISSUE}.json"
        fi
        ;;

    connect)
        echo "Connecting to session: $SESSION_NAME"

        if command -v paude &> /dev/null; then
            paude connect "$SESSION_NAME"
        else
            echo "Connect requires paude to be installed"
        fi
        ;;

    query)
        QUERY="$2"
        PROVIDER="${3:-${HARNESS_AI_PROVIDER:-claude}}"

        echo "Query: $QUERY"
        echo "Provider: $PROVIDER"
        echo ""
        echo "Note: Direct queries require paude + AI credentials"
        ;;

    help|*)
        echo "Paude Session Manager"
        echo ""
        echo "Usage: paude-session.sh <action> [args]"
        echo ""
        echo "Actions:"
        echo "  create              Create a new session for current issue"
        echo "  start               Start/resume session"
        echo "  stop                Stop session"
        echo "  list                List harness sessions"
        echo "  cleanup             Stop and remove all harness sessions"
        echo "  run <task> [prov]   Run a task in the agent"
        echo "  connect             Connect to a running session"
        echo "  query <text>        Run a single query"
        ;;
esac
