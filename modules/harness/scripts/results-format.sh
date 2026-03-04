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
            UNIT_COUNT=$(echo "$TESTS" | jq '[.[] | select(.repo == "local" or .test_type == "unit")] | length')
            FUNC_COUNT=$(echo "$TESTS" | jq '[.[] | select(.repo == "functional" or .test_type == "functional")] | length')

            echo "Generated **$TEST_COUNT** test(s): $UNIT_COUNT unit, $FUNC_COUNT functional"
            echo ""

            UNIT_TESTS=$(echo "$TESTS" | jq '[.[] | select(.repo == "local" or .test_type == "unit")]')
            FUNC_TESTS=$(echo "$TESTS" | jq '[.[] | select(.repo == "functional" or .test_type == "functional")]')

            if [ "$(echo "$UNIT_TESTS" | jq 'length')" -gt 0 ]; then
                echo "### Unit Tests (local repo)"
                echo ""
                echo "$UNIT_TESTS" | jq -r '.[] | "#### \(.test_name)\n\n**File:** \(.file_path)\n**Source:** \(.source_requirement)\n\n```\n\(.code)\n```\n"'
            fi

            if [ "$(echo "$FUNC_TESTS" | jq 'length')" -gt 0 ]; then
                echo "### Functional Tests (functional test repo — requires aap-dev)"
                echo ""
                echo "$FUNC_TESTS" | jq -r '.[] | "#### \(.test_name)\n\n**File:** \(.file_path)\n**Source:** \(.source_requirement)\n\n```\n\(.code)\n```\n"'
                echo ""
                echo "> Run \`make harness/commit-func-tests\` to branch, commit, and open a PR in the functional test repo."
            fi
            ;;

        test-discovery)
            echo "## Test Discovery"
            echo ""

            COVERED=$(jq '.result.covered // []' "$RESULT_FILE")
            GAPS=$(jq '.result.gaps // []' "$RESULT_FILE")
            FUNC_REPO=$(jq -r '._meta.func_test_repo // "not configured"' "$RESULT_FILE")

            UNIT_COVERED=$(echo "$COVERED" | jq '[.[] | select(.test_category == "unit")] | length')
            FUNC_COVERED=$(echo "$COVERED" | jq '[.[] | select(.test_category == "functional")] | length')

            echo "**Unit tests found:** $UNIT_COVERED  |  **Functional tests found:** $FUNC_COVERED"
            echo "**Functional test repo:** $FUNC_REPO"
            echo ""

            echo "### Unit Test Coverage (local repo)"
            UNIT_TESTS=$(echo "$COVERED" | jq '[.[] | select(.test_category == "unit")]')
            if [ "$(echo "$UNIT_TESTS" | jq 'length')" -gt 0 ]; then
                echo "$UNIT_TESTS" | jq -r '.[] | "- \(.test_file) covers \(.covers | join(", "))\n  Tests: \(.test_names | join(", "))"'
            else
                echo "No unit test coverage found"
            fi

            echo ""
            echo "### Functional Test Coverage (functional test repo)"
            FUNC_TESTS=$(echo "$COVERED" | jq '[.[] | select(.test_category == "functional")]')
            if [ "$(echo "$FUNC_TESTS" | jq 'length')" -gt 0 ]; then
                echo "$FUNC_TESTS" | jq -r '.[] | "- \(.test_file) covers \(.covers | join(", "))\n  Tests: \(.test_names | join(", "))"'
            else
                echo "No functional test coverage found"
            fi

            echo ""
            echo "### Coverage Gaps"
            if [ "$(echo "$GAPS" | jq 'length')" -gt 0 ]; then
                echo "$GAPS" | jq -r '.[] | "- \(.file) (\(.symbol))\n  Suggested unit:       \(.suggested_unit_test)\n  Suggested functional: \(.suggested_func_test)"'
                echo ""
                echo "> Run \`make harness/suggest-tests\` to generate tests for these gaps."
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
