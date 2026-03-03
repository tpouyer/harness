#!/bin/bash
# Render prompt templates with context

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"
PROMPTS_DIR="${HARNESS_PATH}/modules/harness/prompts"
PROJECT_PROMPTS=".harness/prompts"

TASK_TYPE="${1:-intent-check}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")

# Load context
JIRA_CONTEXT="$CACHE_DIR/jira-context-${ISSUE}.json"
CODE_CONTEXT="$CACHE_DIR/code-context-${ISSUE}.json"

# Export variables for envsubst
if [ -f "$JIRA_CONTEXT" ]; then
    export ISSUE_KEY=$(jq -r '.issue.key' "$JIRA_CONTEXT")
    export ISSUE_SUMMARY=$(jq -r '.issue.summary' "$JIRA_CONTEXT")
    export ISSUE_TYPE=$(jq -r '.issue.type' "$JIRA_CONTEXT")
    export ISSUE_STATUS=$(jq -r '.issue.status' "$JIRA_CONTEXT")
    export ISSUE_DESCRIPTION=$(jq -r '.issue.description // ""' "$JIRA_CONTEXT")
    export ACCEPTANCE_CRITERIA=$(jq -r '.issue.acceptance_criteria | join("\n")' "$JIRA_CONTEXT")
    export EPIC_KEY=$(jq -r '.epic.key // "None"' "$JIRA_CONTEXT")
    export EPIC_SUMMARY=$(jq -r '.epic.summary // ""' "$JIRA_CONTEXT")
    export EPIC_DESCRIPTION=$(jq -r '.epic.description // ""' "$JIRA_CONTEXT")
    export COMMENTS=$(jq -r '.comments[] | "[\(.author)]: \(.body)"' "$JIRA_CONTEXT" 2>/dev/null | head -20 || echo "")
else
    export ISSUE_KEY="$ISSUE"
    export ISSUE_SUMMARY="[Context not available]"
    export ISSUE_TYPE="Unknown"
    export ISSUE_STATUS="Unknown"
    export ISSUE_DESCRIPTION=""
    export ACCEPTANCE_CRITERIA=""
    export EPIC_KEY="None"
    export EPIC_SUMMARY=""
    export EPIC_DESCRIPTION=""
    export COMMENTS=""
fi

if [ -f "$CODE_CONTEXT" ]; then
    export CODE_LANGUAGE=$(jq -r '.repository.detected_language' "$CODE_CONTEXT")
    export CODE_ADDITIONS=$(jq -r '.changes.total_additions' "$CODE_CONTEXT")
    export CODE_DELETIONS=$(jq -r '.changes.total_deletions' "$CODE_CONTEXT")
    export CODE_FILE_COUNT=$(jq -r '.changes.file_count' "$CODE_CONTEXT")
    export CODE_FILES=$(jq -r '.changes.files[] | "- \(.path) (\(.status))"' "$CODE_CONTEXT" | head -30)
    export CODE_DIFF_SUMMARY=$(jq -r '.diffs.branch_summary' "$CODE_CONTEXT")
    export RECENT_COMMITS=$(jq -r '.recent_commits | join("\n")' "$CODE_CONTEXT")
else
    export CODE_LANGUAGE="unknown"
    export CODE_ADDITIONS="0"
    export CODE_DELETIONS="0"
    export CODE_FILE_COUNT="0"
    export CODE_FILES=""
    export CODE_DIFF_SUMMARY=""
    export RECENT_COMMITS=""
fi

# Build epic context section
if [ "$EPIC_KEY" != "None" ] && [ -n "$EPIC_SUMMARY" ]; then
    export EPIC_CONTEXT="### Epic Context
Epic: ${EPIC_KEY} - ${EPIC_SUMMARY}

${EPIC_DESCRIPTION}"
else
    export EPIC_CONTEXT=""
fi

# Find template directory (project overrides take precedence)
if [ -d "$PROJECT_PROMPTS/$TASK_TYPE" ]; then
    TEMPLATE_DIR="$PROJECT_PROMPTS/$TASK_TYPE"
elif [ -d "$PROMPTS_DIR/$TASK_TYPE" ]; then
    TEMPLATE_DIR="$PROMPTS_DIR/$TASK_TYPE"
else
    echo "Error: No template found for task type: $TASK_TYPE" >&2
    echo "Checked: $PROJECT_PROMPTS/$TASK_TYPE, $PROMPTS_DIR/$TASK_TYPE" >&2
    exit 1
fi

# Render templates in order
render_template() {
    local file="$1"
    if [ -f "$file" ]; then
        envsubst < "$file"
        echo ""
    fi
}

# System prompt first
render_template "$TEMPLATE_DIR/system.md"

# Task-specific templates
case "$TASK_TYPE" in
    intent-check)
        render_template "$TEMPLATE_DIR/jira-analysis.md"
        render_template "$TEMPLATE_DIR/code-analysis.md"
        render_template "$TEMPLATE_DIR/comparison.md"
        ;;
    test-generation)
        render_template "$TEMPLATE_DIR/requirements.md"
        render_template "$TEMPLATE_DIR/code-context.md"
        render_template "$TEMPLATE_DIR/generation.md"
        ;;
    assist)
        render_template "$TEMPLATE_DIR/context.md"
        render_template "$TEMPLATE_DIR/instructions.md"
        ;;
    *)
        # Generic: render all .md files in order
        for file in "$TEMPLATE_DIR"/*.md; do
            render_template "$file"
        done
        ;;
esac
