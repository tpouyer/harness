#!/bin/bash
# Assemble combined context from Jira and code analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"

ACTION="${1:-assemble}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")

JIRA_CONTEXT="$CACHE_DIR/jira-context-${ISSUE}.json"
CODE_CONTEXT="$CACHE_DIR/code-context-${ISSUE}.json"
COMBINED_CONTEXT="$CACHE_DIR/context-${ISSUE}.json"

case "$ACTION" in
    show)
        echo ""
        echo "Issue: $ISSUE"
        echo ""

        if [ -f "$JIRA_CONTEXT" ]; then
            echo "Jira Context:"
            echo "  Summary: $(jq -r '.issue.summary' "$JIRA_CONTEXT")"
            echo "  Type: $(jq -r '.issue.type' "$JIRA_CONTEXT")"
            echo "  Status: $(jq -r '.issue.status' "$JIRA_CONTEXT")"
            EPIC=$(jq -r '.epic.key // "None"' "$JIRA_CONTEXT")
            echo "  Epic: $EPIC"
            AC_COUNT=$(jq '.issue.acceptance_criteria | length' "$JIRA_CONTEXT")
            echo "  Acceptance Criteria: $AC_COUNT item(s)"
            COMMENT_COUNT=$(jq '.comments | length' "$JIRA_CONTEXT")
            echo "  Comments: $COMMENT_COUNT"

            # Show hierarchy
            HIERARCHY_COUNT=$(jq '.hierarchy | length // 0' "$JIRA_CONTEXT" 2>/dev/null || echo "0")
            if [ "$HIERARCHY_COUNT" -gt 0 ]; then
                echo ""
                echo "  Strategic Hierarchy:"
                jq -r '.hierarchy[] | "    \(.type | ascii_upcase): \(.key) - \(.summary)"' "$JIRA_CONTEXT" 2>/dev/null || true
            fi

            # Show handbook documents
            DOC_COUNT=$(jq '.handbook_documents.documents | length // 0' "$JIRA_CONTEXT" 2>/dev/null || echo "0")
            if [ "$DOC_COUNT" -gt 0 ]; then
                echo ""
                echo "  Handbook Documents: $DOC_COUNT found"
                jq -r '.handbook_documents.documents[] | "    [\(.type)] \(.title) (from \(.source_issue))"' "$JIRA_CONTEXT" 2>/dev/null || true
            fi
        else
            echo "Jira Context: Not available"
        fi

        echo ""

        if [ -f "$CODE_CONTEXT" ]; then
            echo "Code Context:"
            echo "  Language: $(jq -r '.repository.detected_language' "$CODE_CONTEXT")"
            echo "  Files Changed: $(jq -r '.changes.file_count' "$CODE_CONTEXT")"
            echo "  Additions: +$(jq -r '.changes.total_additions' "$CODE_CONTEXT")"
            echo "  Deletions: -$(jq -r '.changes.total_deletions' "$CODE_CONTEXT")"
            echo ""
            echo "  Modified Files:"
            jq -r '.changes.files[] | "    \(.status): \(.path)"' "$CODE_CONTEXT" | head -20
        else
            echo "Code Context: Not available"
        fi
        ;;

    assemble)
        # Combine contexts
        JIRA_DATA="{}"
        CODE_DATA="{}"

        if [ -f "$JIRA_CONTEXT" ]; then
            JIRA_DATA=$(cat "$JIRA_CONTEXT")
        fi

        if [ -f "$CODE_CONTEXT" ]; then
            CODE_DATA=$(cat "$CODE_CONTEXT")
        fi

        jq -n \
            --argjson jira "$JIRA_DATA" \
            --argjson code "$CODE_DATA" \
            --arg issue "$ISSUE" \
            '{
                issue: $issue,
                jira: $jira,
                code: $code,
                _meta: {
                    assembled_at: (now | todate)
                }
            }' > "$COMBINED_CONTEXT"

        echo "Combined context saved to $COMBINED_CONTEXT"
        ;;

    *)
        echo "Usage: context-assemble.sh [show|assemble]" >&2
        exit 1
        ;;
esac
