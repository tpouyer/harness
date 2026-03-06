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

# Container image based on provider
get_container_image() {
    local provider="$1"
    echo "${HARNESS_CONTAINER_REGISTRY:-quay.io/aap}/harness-${provider}:latest"
}

case "$ACTION" in
    create)
        echo "Creating paude session: $SESSION_NAME"

        IMAGE=$(get_container_image "$PROVIDER")
        ALLOWED="${HARNESS_PAUDE_ALLOWED_DOMAINS:-api.anthropic.com,api.openai.com}"

        # Build GCP mount flags for Claude via Vertex AI
        GCP_FLAGS=""
        if [ "$PROVIDER" = "claude" ] && [ -n "$GCP_PROJECT_ID" ]; then
            ADC_DIR="$HOME/.config/gcloud"
            if [ -d "$ADC_DIR" ]; then
                GCP_FLAGS="--mount $ADC_DIR/application_default_credentials.json:/tmp/adc.json:z"
            fi
            GCP_FLAGS="$GCP_FLAGS --env GCP_PROJECT_ID=$GCP_PROJECT_ID"
            GCP_FLAGS="$GCP_FLAGS --env GCP_REGION=${GCP_REGION:-us-east5}"
            GCP_FLAGS="$GCP_FLAGS --env GCP_QUOTA_PROJECT=${GCP_QUOTA_PROJECT:-$GCP_PROJECT_ID}"
        fi

        if command -v paude &> /dev/null; then
            # shellcheck disable=SC2086
            paude create --yolo \
                --image "$IMAGE" \
                --allowed-domains "$ALLOWED" \
                $GCP_FLAGS \
                "$SESSION_NAME" || {
                    echo "Note: paude create failed - this may be expected if paude is not fully configured"
                }
        else
            echo "Warning: paude not installed"
            echo "Would create session with:"
            echo "  Name: $SESSION_NAME"
            echo "  Image: $IMAGE"
            echo "  Allowed domains: $ALLOWED"
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

    logs)
        if command -v paude &> /dev/null; then
            paude logs "$SESSION_NAME"
        fi
        ;;

    cleanup)
        echo "Cleaning up harness sessions..."
        if command -v paude &> /dev/null; then
            paude list 2>/dev/null | grep "harness-" | while read -r session; do
                paude stop "$session" 2>/dev/null || true
                paude rm "$session" 2>/dev/null || true
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

        # In production, this would invoke paude to run the agent
        # For now, simulate the call
        if command -v paude &> /dev/null && paude list 2>/dev/null | grep -q "$SESSION_NAME"; then
            # Mount context and run
            paude exec "$SESSION_NAME" \
                --mount "$CACHE_DIR:/workspace/.harness" \
                -- cat /workspace/.harness/prompt-${ISSUE}.md
        else
            echo "Note: Running in simulation mode (paude not available)"
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
                        summary: "This is a simulated response. Configure paude and AI credentials for real results.",
                        details: []
                    },
                    _meta: {
                        completed_at: (now | todate)
                    }
                }' > "$CACHE_DIR/result-${ISSUE}.json"
        fi
        ;;

    interactive)
        echo "Starting interactive session for: $TASK_TYPE"
        echo "Provider: $PROVIDER"
        echo ""

        if command -v paude &> /dev/null; then
            "$SCRIPT_DIR/prompt-render.sh" "$TASK_TYPE" > "$CACHE_DIR/prompt-${ISSUE}.md"
            paude interactive "$SESSION_NAME" --context "$CACHE_DIR/prompt-${ISSUE}.md"
        else
            echo "Interactive mode requires paude to be installed"
            echo "Install with: pip install paude"
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
        echo "  logs                Show session logs"
        echo "  cleanup             Stop and remove all harness sessions"
        echo "  run <task> [prov]   Run a task in the agent"
        echo "  interactive <task>  Start interactive session"
        echo "  query <text>        Run a single query"
        ;;
esac
