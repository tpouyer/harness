#!/bin/bash
# Discover existing tests that cover modified code.
# Searches the local repo for unit tests and, if configured,
# the functional test repo for functional (aap-dev) tests.

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

LANGUAGE=$(jq -r '.repository.detected_language' "$CODE_CONTEXT")
MODIFIED_FILES=$(jq -r '.changes.files[].path' "$CODE_CONTEXT")

COVERED="[]"
GAPS="[]"

# ---------------------------------------------------------------------------
# Helper: search a directory for tests matching a source file
# Arguments: source_file language search_root test_category repo_label repo_path
# ---------------------------------------------------------------------------
search_tests_for_file() {
    local file="$1"
    local language="$2"
    local search_root="$3"
    local test_category="$4"
    local repo_label="$5"
    local repo_path="$6"

    local BASENAME
    BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')
    local DIRNAME
    DIRNAME=$(dirname "$file")

    local PATTERNS=()
    case "$language" in
        python)
            PATTERNS+=("test_${BASENAME}.py" "${BASENAME}_test.py")
            ;;
        typescript|javascript)
            PATTERNS+=("${BASENAME}.test.ts" "${BASENAME}.test.js" "${BASENAME}.spec.ts" "${BASENAME}.spec.js")
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

    local FOUND_TEST=""
    for pattern in "${PATTERNS[@]}"; do
        local MATCHES
        MATCHES=$(find "$search_root" -name "$pattern" -type f 2>/dev/null | head -1 || true)
        if [ -n "$MATCHES" ]; then
            FOUND_TEST="$MATCHES"
            break
        fi
    done

    # Fallback: grep for the basename inside test files in the search root
    if [ -z "$FOUND_TEST" ]; then
        case "$language" in
            python)
                FOUND_TEST=$(grep -rl "$BASENAME" "$search_root" --include="test_*.py" --include="*_test.py" 2>/dev/null | head -1 || true)
                ;;
            typescript|javascript)
                FOUND_TEST=$(grep -rl "$BASENAME" "$search_root" --include="*.test.ts" --include="*.test.js" --include="*.spec.ts" --include="*.spec.js" 2>/dev/null | head -1 || true)
                ;;
            go)
                FOUND_TEST=$(grep -rl "$BASENAME" "$search_root" --include="*_test.go" 2>/dev/null | head -1 || true)
                ;;
        esac
    fi

    echo "$FOUND_TEST|$test_category|$repo_label|$repo_path|$BASENAME"
}

# ---------------------------------------------------------------------------
# Extract test names from a found test file
# ---------------------------------------------------------------------------
extract_test_names() {
    local found_test="$1"
    local language="$2"

    local TEST_NAMES="[]"
    case "$language" in
        python)
            TEST_NAMES=$(grep -E '^\s*def test_' "$found_test" 2>/dev/null \
                | sed 's/.*def \(test_[^(]*\).*/\1/' \
                | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
            ;;
        typescript|javascript)
            TEST_NAMES=$(grep -E "(it|test|describe)\(['\"]" "$found_test" 2>/dev/null \
                | sed "s/.*['\"]\\([^'\"]*\\)['\"].*/\\1/" \
                | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
            ;;
        go)
            TEST_NAMES=$(grep -E '^func Test' "$found_test" 2>/dev/null \
                | sed 's/func \(Test[^(]*\).*/\1/' \
                | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")
            ;;
    esac
    echo "$TEST_NAMES"
}

# ---------------------------------------------------------------------------
# Resolve and validate the functional test repo path
# ---------------------------------------------------------------------------
FUNC_REPO=""
if [ -n "$HARNESS_FUNC_TEST_REPO" ]; then
    # Expand ~ and relative paths
    FUNC_REPO=$(eval echo "$HARNESS_FUNC_TEST_REPO")
    if [ ! -d "$FUNC_REPO" ]; then
        echo "Warning: HARNESS_FUNC_TEST_REPO path not found: $FUNC_REPO" >&2
        echo "  Functional test discovery skipped." >&2
        FUNC_REPO=""
    fi
fi

# ---------------------------------------------------------------------------
# Main discovery loop
# ---------------------------------------------------------------------------
echo "Discovering tests for modified code..."
[ -n "$FUNC_REPO" ] && echo "  Unit tests:       $(pwd)"
[ -n "$FUNC_REPO" ] && echo "  Functional tests: $FUNC_REPO"

while IFS= read -r file; do
    [ -z "$file" ] && continue

    BASENAME=$(basename "$file" | sed 's/\.[^.]*$//')

    # --- Unit test search (local repo) ---
    UNIT_RESULT=$(search_tests_for_file "$file" "$LANGUAGE" "." "unit" "local" "$(pwd)")
    UNIT_FOUND=$(echo "$UNIT_RESULT" | cut -d'|' -f1)

    if [ -n "$UNIT_FOUND" ]; then
        TEST_NAMES=$(extract_test_names "$UNIT_FOUND" "$LANGUAGE")
        COVERED=$(echo "$COVERED" | jq \
            --arg test_file "$UNIT_FOUND" \
            --arg source_file "$file" \
            --argjson test_names "$TEST_NAMES" \
            --arg test_category "unit" \
            --arg repo "local" \
            '. + [{
                test_file: $test_file,
                covers: [$source_file],
                test_names: $test_names,
                test_category: $test_category,
                repo: $repo,
                match_type: "structural"
            }]')
    fi

    # --- Functional test search (separate repo) ---
    FUNC_FOUND=""
    if [ -n "$FUNC_REPO" ]; then
        FUNC_RESULT=$(search_tests_for_file "$file" "$LANGUAGE" "$FUNC_REPO" "functional" "functional" "$FUNC_REPO")
        FUNC_FOUND=$(echo "$FUNC_RESULT" | cut -d'|' -f1)

        if [ -n "$FUNC_FOUND" ]; then
            TEST_NAMES=$(extract_test_names "$FUNC_FOUND" "$LANGUAGE")
            COVERED=$(echo "$COVERED" | jq \
                --arg test_file "$FUNC_FOUND" \
                --arg source_file "$file" \
                --argjson test_names "$TEST_NAMES" \
                --arg test_category "functional" \
                --arg repo "$FUNC_REPO" \
                '. + [{
                    test_file: $test_file,
                    covers: [$source_file],
                    test_names: $test_names,
                    test_category: $test_category,
                    repo: $repo,
                    match_type: "structural"
                }]')
        fi
    fi

    # Track gaps: neither unit nor functional coverage found
    if [ -z "$UNIT_FOUND" ] && [ -z "$FUNC_FOUND" ]; then
        GAPS=$(echo "$GAPS" | jq \
            --arg file "$file" \
            --arg basename "$BASENAME" \
            '. + [{
                file: $file,
                symbol: $basename,
                suggested_unit_test: "test_\($basename)",
                suggested_func_test: "test_\($basename)_functional"
            }]')
    fi

done <<< "$MODIFIED_FILES"

# ---------------------------------------------------------------------------
# Build result
# ---------------------------------------------------------------------------
FUNC_REPO_LABEL="${FUNC_REPO:-not configured}"

jq -n \
    --argjson covered "$COVERED" \
    --argjson gaps "$GAPS" \
    --arg func_repo "$FUNC_REPO_LABEL" \
    '{
        covered: $covered,
        gaps: $gaps,
        _meta: {
            discovered_at: (now | todate),
            method: "structural",
            func_test_repo: $func_repo
        }
    }' > "$RESULT_FILE"

COVERED_UNIT=$(echo "$COVERED" | jq '[.[] | select(.test_category == "unit")] | length')
COVERED_FUNC=$(echo "$COVERED" | jq '[.[] | select(.test_category == "functional")] | length')
GAP_COUNT=$(echo "$GAPS" | jq 'length')

echo "Discovery complete:"
echo "  Unit tests found:       $COVERED_UNIT"
echo "  Functional tests found: $COVERED_FUNC"
echo "  Coverage gaps:          $GAP_COUNT"
