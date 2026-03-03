#!/bin/bash
# Analyze local code changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"

# Detect issue for cache naming
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")
CACHE_FILE="$CACHE_DIR/code-context-${ISSUE}.json"

echo "Analyzing code changes..."

# Ensure we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not a git repository" >&2
    exit 1
fi

# Find merge base with main/master
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
MERGE_BASE=$(git merge-base HEAD "origin/${MAIN_BRANCH}" 2>/dev/null || git merge-base HEAD "${MAIN_BRANCH}" 2>/dev/null || git rev-parse HEAD~10 2>/dev/null || echo "")

# Get diffs
BRANCH_DIFF=""
STAGED_DIFF=""
WORKING_DIFF=""

if [ -n "$MERGE_BASE" ]; then
    BRANCH_DIFF=$(git diff "$MERGE_BASE"..HEAD --stat 2>/dev/null || echo "")
    BRANCH_DIFF_FULL=$(git diff "$MERGE_BASE"..HEAD 2>/dev/null || echo "")
fi

STAGED_DIFF=$(git diff --cached --stat 2>/dev/null || echo "")
STAGED_DIFF_FULL=$(git diff --cached 2>/dev/null || echo "")

WORKING_DIFF=$(git diff --stat 2>/dev/null || echo "")
WORKING_DIFF_FULL=$(git diff 2>/dev/null || echo "")

# Get modified files
MODIFIED_FILES=$(git diff --name-only "$MERGE_BASE"..HEAD 2>/dev/null || echo "")
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
WORKING_FILES=$(git diff --name-only 2>/dev/null || echo "")

# Combine all modified files
ALL_FILES=$(echo -e "${MODIFIED_FILES}\n${STAGED_FILES}\n${WORKING_FILES}" | sort -u | grep -v '^$' || true)

# Count changes
BRANCH_ADDITIONS=$(echo "$BRANCH_DIFF_FULL" | grep -c '^+[^+]' 2>/dev/null || echo "0")
BRANCH_DELETIONS=$(echo "$BRANCH_DIFF_FULL" | grep -c '^-[^-]' 2>/dev/null || echo "0")

# Detect language from modified files
detect_language() {
    local files="$1"

    if echo "$files" | grep -qE '\.py$'; then
        echo "python"
    elif echo "$files" | grep -qE '\.ts$|\.tsx$'; then
        echo "typescript"
    elif echo "$files" | grep -qE '\.js$|\.jsx$'; then
        echo "javascript"
    elif echo "$files" | grep -qE '\.go$'; then
        echo "go"
    elif echo "$files" | grep -qE '\.java$'; then
        echo "java"
    elif echo "$files" | grep -qE '\.rs$'; then
        echo "rust"
    elif echo "$files" | grep -qE '\.rb$'; then
        echo "ruby"
    else
        echo "unknown"
    fi
}

DETECTED_LANGUAGE=$(detect_language "$ALL_FILES")

# Extract modified symbols (simplified - would use tree-sitter in production)
extract_symbols() {
    local file="$1"
    local lang="$2"

    if [ ! -f "$file" ]; then
        return
    fi

    case "$lang" in
        python)
            grep -E '^\s*(def |class |async def )' "$file" 2>/dev/null | sed 's/^[[:space:]]*//' | head -20 || true
            ;;
        typescript|javascript)
            grep -E '^\s*(export |function |class |const |interface |type )' "$file" 2>/dev/null | sed 's/^[[:space:]]*//' | head -20 || true
            ;;
        go)
            grep -E '^(func |type )' "$file" 2>/dev/null | head -20 || true
            ;;
        java)
            grep -E '^\s*(public |private |protected )?(class |interface |void |static )' "$file" 2>/dev/null | sed 's/^[[:space:]]*//' | head -20 || true
            ;;
        *)
            echo ""
            ;;
    esac
}

# Build file details
FILE_DETAILS="[]"
FILE_COUNT=0
MAX_FILES="${HARNESS_MAX_FILES:-50}"

while IFS= read -r file; do
    if [ -z "$file" ] || [ $FILE_COUNT -ge $MAX_FILES ]; then
        continue
    fi

    FILE_COUNT=$((FILE_COUNT + 1))

    # Get file status
    if git diff --cached --name-only | grep -q "^${file}$" 2>/dev/null; then
        STATUS="staged"
    elif git diff --name-only | grep -q "^${file}$" 2>/dev/null; then
        STATUS="modified"
    else
        STATUS="committed"
    fi

    # Get symbols
    SYMBOLS=$(extract_symbols "$file" "$DETECTED_LANGUAGE" | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo "[]")

    FILE_DETAILS=$(echo "$FILE_DETAILS" | jq \
        --arg path "$file" \
        --arg status "$STATUS" \
        --argjson symbols "$SYMBOLS" \
        '. + [{path: $path, status: $status, symbols: $symbols}]')
done <<< "$ALL_FILES"

# Get recent commits
RECENT_COMMITS=$(git log --oneline -10 2>/dev/null | jq -R -s 'split("\n") | map(select(. != ""))' || echo "[]")

# Build context document
jq -n \
    --arg issue "$ISSUE" \
    --arg merge_base "$MERGE_BASE" \
    --arg main_branch "$MAIN_BRANCH" \
    --arg language "$DETECTED_LANGUAGE" \
    --argjson additions "$BRANCH_ADDITIONS" \
    --argjson deletions "$BRANCH_DELETIONS" \
    --argjson file_count "$FILE_COUNT" \
    --argjson files "$FILE_DETAILS" \
    --argjson commits "$RECENT_COMMITS" \
    --arg branch_diff "$BRANCH_DIFF" \
    --arg staged_diff "$STAGED_DIFF" \
    --arg working_diff "$WORKING_DIFF" \
    '{
        issue: $issue,
        repository: {
            merge_base: $merge_base,
            main_branch: $main_branch,
            detected_language: $language
        },
        changes: {
            total_additions: $additions,
            total_deletions: $deletions,
            file_count: $file_count,
            files: $files
        },
        diffs: {
            branch_summary: $branch_diff,
            staged_summary: $staged_diff,
            working_summary: $working_diff
        },
        recent_commits: $commits,
        _meta: {
            analyzed_at: (now | todate)
        }
    }' > "$CACHE_FILE"

echo "Code context saved to $CACHE_FILE"
echo "  Files analyzed: $FILE_COUNT"
echo "  Language: $DETECTED_LANGUAGE"
echo "  Changes: +$BRANCH_ADDITIONS -$BRANCH_DELETIONS"
