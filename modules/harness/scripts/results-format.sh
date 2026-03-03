#!/bin/bash
# Format and display results from agent execution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"
OUTPUT_FORMAT="${HARNESS_OUTPUT_FORMAT:-markdown}"

TASK_TYPE="${1:-intent-check}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")
RESULT_FILE="$CACHE_DIR/result-${ISSUE}.json"

if [ ! -f "$RESULT_FILE" ]; then
    echo "No results found for $ISSUE" >&2
    exit 1
fi

format_markdown() {
    local task="$1"

    echo ""
    echo "# Harness Results: $task"
    echo ""
    echo "**Issue:** $(jq -r '.issue' "$RESULT_FILE")"
    echo "**Provider:** $(jq -r '.provider' "$RESULT_FILE")"
    echo "**Status:** $(jq -r '.status' "$RESULT_FILE")"
    echo ""

    case "$task" in
        intent-check)
            echo "## Intent Alignment"
            echo ""

            ALIGNMENT=$(jq -r '.result.overall_alignment // "unknown"' "$RESULT_FILE")
            SCORE=$(jq -r '.result.score // "N/A"' "$RESULT_FILE")

            case "$ALIGNMENT" in
                aligned)
                    echo "**Result:** ✅ Aligned (Score: $SCORE/100)"
                    ;;
                partial)
                    echo "**Result:** ⚠️ Partial Alignment (Score: $SCORE/100)"
                    ;;
                divergent)
                    echo "**Result:** ❌ Divergent (Score: $SCORE/100)"
                    ;;
                *)
                    echo "**Result:** $ALIGNMENT"
                    ;;
            esac

            echo ""
            echo "### Summary"
            jq -r '.result.summary // "No summary available"' "$RESULT_FILE"

            CONCERNS=$(jq '.result.concerns // []' "$RESULT_FILE")
            if [ "$(echo "$CONCERNS" | jq 'length')" -gt 0 ]; then
                echo ""
                echo "### Concerns"
                echo "$CONCERNS" | jq -r '.[] | "- **\(.severity)**: \(.description)"'
            fi

            RECOMMENDATIONS=$(jq '.result.recommendations // []' "$RESULT_FILE")
            if [ "$(echo "$RECOMMENDATIONS" | jq 'length')" -gt 0 ]; then
                echo ""
                echo "### Recommendations"
                echo "$RECOMMENDATIONS" | jq -r '.[] | "- \(.)"'
            fi
            ;;

        test-generation)
            echo "## Generated Tests"
            echo ""

            TESTS=$(jq '.result.tests // []' "$RESULT_FILE")
            TEST_COUNT=$(echo "$TESTS" | jq 'length')

            echo "Generated **$TEST_COUNT** test(s)"
            echo ""

            echo "$TESTS" | jq -r '.[] | "### \(.test_name)\n\n**File:** \(.file_path)\n**Type:** \(.test_type)\n**Source:** \(.source_requirement)\n\n```\n\(.code)\n```\n"'
            ;;

        test-discovery)
            echo "## Test Discovery"
            echo ""

            COVERED=$(jq '.result.covered // []' "$RESULT_FILE")
            GAPS=$(jq '.result.gaps // []' "$RESULT_FILE")

            echo "### Covered by Existing Tests"
            if [ "$(echo "$COVERED" | jq 'length')" -gt 0 ]; then
                echo "$COVERED" | jq -r '.[] | "- \(.test_file):\(.test_name) covers \(.covers | join(", "))"'
            else
                echo "No existing test coverage found"
            fi

            echo ""
            echo "### Coverage Gaps"
            if [ "$(echo "$GAPS" | jq 'length')" -gt 0 ]; then
                echo "$GAPS" | jq -r '.[] | "- \(.file):\(.symbol) - Suggested: \(.suggested_test)"'
            else
                echo "No coverage gaps identified"
            fi
            ;;

        *)
            echo "## Result"
            echo ""
            jq -r '.result' "$RESULT_FILE"
            ;;
    esac

    echo ""
    echo "---"
    echo "*Completed: $(jq -r '._meta.completed_at // "unknown"' "$RESULT_FILE")*"
}

format_json() {
    cat "$RESULT_FILE"
}

case "$OUTPUT_FORMAT" in
    json)
        format_json
        ;;
    markdown|*)
        format_markdown "$TASK_TYPE"
        ;;
esac
