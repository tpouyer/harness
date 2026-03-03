#!/bin/bash
# Discover existing tests that cover modified code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")
CODE_CONTEXT="$CACHE_DIR/code-context-${ISSUE}.json"
RESULT_FILE="$CACHE_DIR/test-discovery-${ISSUE}.json"

if [ ! -f "$CODE_CONTEXT" ]; then
    echo "Error: Code context not found. Run harness/context first." >&2
    exit 1
fi

echo "Discovering tests for modified code..."

LANGUAGE=$(jq -r '.repository.detected_language' "$CODE_CONTEXT")
MODIFIED_FILES=$(jq -r '.changes.files[].path' "$CODE_CONTEXT")

COVERED="[]"
GAPS="[]"

# Find test directories
TEST_DIRS=""
for pattern in "tests" "test" "__tests__" "spec" "*_test" "test_*"; do
    if ls -d $pattern 2>/dev/null; then
        TEST_DIRS="$TEST_DIRS $(ls -d $pattern 2>/dev/null)"
    fi
done

# Match modified files to tests
while IFS= read -r file; do
    [ -z "$file" ] && continue

    BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')
    DIRNAME=$(dirname "$file")

    # Generate possible test file patterns
    PATTERNS=()
    case "$LANGUAGE" in
        python)
            PATTERNS+=("test_${BASENAME}.py" "${BASENAME}_test.py" "tests/test_${BASENAME}.py")
            ;;
        typescript|javascript)
            PATTERNS+=("${BASENAME}.test.ts" "${BASENAME}.test.js" "${BASENAME}.spec.ts" "${BASENAME}.spec.js")
            PATTERNS+=("__tests__/${BASENAME}.test.ts" "__tests__/${BASENAME}.test.js")
            ;;
        go)
            PATTERNS+=("${BASENAME}_test.go" "${DIRNAME}/${BASENAME}_test.go")
            ;;
        java)
            PATTERNS+=("${BASENAME}Test.java" "Test${BASENAME}.java")
            ;;
        *)
            PATTERNS+=("test_${BASENAME}.*" "${BASENAME}_test.*" "${BASENAME}.test.*")
            ;;
    esac

    FOUND_TEST=""
    for pattern in "${PATTERNS[@]}"; do
        MATCHES=$(find . -name "$pattern" -type f 2>/dev/null | head -1 || true)
        if [ -n "$MATCHES" ]; then
            FOUND_TEST="$MATCHES"
            break
        fi
    done

    if [ -n "$FOUND_TEST" ]; then
        # Extract test names from the file
        TEST_NAMES="[]"
        case "$LANGUAGE" in
            python)
                TEST_NAMES=$(grep -E '^\s*def test_' "$FOUND_TEST" 2>/dev/null | sed 's/.*def \(test_[^(]*\).*/\1/' | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
                ;;
            typescript|javascript)
                TEST_NAMES=$(grep -E "(it|test|describe)\(['\"]" "$FOUND_TEST" 2>/dev/null | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
                ;;
            go)
                TEST_NAMES=$(grep -E '^func Test' "$FOUND_TEST" 2>/dev/null | sed 's/func \(Test[^(]*\).*/\1/' | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
                ;;
        esac

        COVERED=$(echo "$COVERED" | jq \
            --arg test_file "$FOUND_TEST" \
            --arg source_file "$file" \
            --argjson test_names "$TEST_NAMES" \
            '. + [{
                test_file: $test_file,
                covers: [$source_file],
                test_names: $test_names,
                match_type: "naming"
            }]')
    else
        # Add to gaps
        GAPS=$(echo "$GAPS" | jq \
            --arg file "$file" \
            --arg basename "$BASENAME" \
            '. + [{
                file: $file,
                symbol: $basename,
                suggested_test: "test_\($basename)"
            }]')
    fi
done <<< "$MODIFIED_FILES"

# Build result
jq -n \
    --argjson covered "$COVERED" \
    --argjson gaps "$GAPS" \
    '{
        covered: $covered,
        gaps: $gaps,
        _meta: {
            discovered_at: (now | todate),
            method: "structural"
        }
    }' > "$RESULT_FILE"

COVERED_COUNT=$(echo "$COVERED" | jq 'length')
GAP_COUNT=$(echo "$GAPS" | jq 'length')

echo "Discovery complete:"
echo "  Tests found: $COVERED_COUNT"
echo "  Coverage gaps: $GAP_COUNT"
