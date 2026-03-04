#!/bin/bash
# Create a feature branch in the functional test repo, commit generated
# functional tests to it, push, and open a GitHub PR.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ -z "$HARNESS_FUNC_TEST_REPO" ]; then
    echo "Error: HARNESS_FUNC_TEST_REPO is not configured." >&2
    echo "  Set it in .harness/config.env, e.g.:" >&2
    echo "    HARNESS_FUNC_TEST_REPO=../my-functional-tests" >&2
    exit 1
fi

FUNC_REPO=$(eval echo "$HARNESS_FUNC_TEST_REPO")

if [ ! -d "$FUNC_REPO/.git" ]; then
    echo "Error: Functional test repo not found at: $FUNC_REPO" >&2
    echo "  Clone it first or check HARNESS_FUNC_TEST_REPO." >&2
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "Warning: 'gh' CLI not installed. Tests will be committed and pushed," >&2
    echo "  but the PR must be opened manually." >&2
fi

# ---------------------------------------------------------------------------
# Locate generated test results
# ---------------------------------------------------------------------------
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")
RESULT_FILE="$CACHE_DIR/result-${ISSUE}.json"

if [ ! -f "$RESULT_FILE" ]; then
    echo "Error: No test generation results found for $ISSUE." >&2
    echo "  Run 'make harness/suggest-tests' first." >&2
    exit 1
fi

# Extract tests where repo == functional or test_type == functional
FUNC_TESTS=$(jq '[
    .result.tests // [] |
    .[] |
    select(.repo == "functional" or .test_type == "functional")
]' "$RESULT_FILE")

FUNC_TEST_COUNT=$(echo "$FUNC_TESTS" | jq 'length')

if [ "$FUNC_TEST_COUNT" -eq 0 ]; then
    echo "No functional tests found in results for $ISSUE."
    echo "  Run 'make harness/suggest-tests' to generate tests, then re-run."
    exit 0
fi

echo "Found $FUNC_TEST_COUNT functional test(s) to commit."

# ---------------------------------------------------------------------------
# Branch setup
# ---------------------------------------------------------------------------
BRANCH_PREFIX="${HARNESS_FUNC_TEST_BRANCH_PREFIX:-harness/}"
BRANCH="${BRANCH_PREFIX}${ISSUE}"
REMOTE="${HARNESS_FUNC_TEST_REMOTE:-origin}"
DEFAULT_BRANCH="${HARNESS_FUNC_TEST_DEFAULT_BRANCH:-main}"

SOURCE_REPO_PATH="$(pwd)"

cd "$FUNC_REPO"

# Fetch latest
echo "Fetching $REMOTE/$DEFAULT_BRANCH..."
git fetch "$REMOTE" "$DEFAULT_BRANCH" 2>/dev/null || echo "  Warning: fetch failed — using local state."

# Create or switch to feature branch
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch '$BRANCH' already exists, switching to it."
    git checkout "$BRANCH"
else
    echo "Creating branch: $BRANCH"
    # Base off the remote default branch if available, else local HEAD
    if git show-ref --verify --quiet "refs/remotes/$REMOTE/$DEFAULT_BRANCH"; then
        git checkout -b "$BRANCH" "$REMOTE/$DEFAULT_BRANCH"
    else
        git checkout -b "$BRANCH"
    fi
fi

# ---------------------------------------------------------------------------
# Write test files
# ---------------------------------------------------------------------------
echo ""
echo "Writing test files..."

WRITTEN_FILES=()

while IFS= read -r test_json; do
    FILE_PATH=$(echo "$test_json" | jq -r '.file_path')
    CODE=$(echo "$test_json" | jq -r '.code')
    TEST_NAME=$(echo "$test_json" | jq -r '.test_name')

    mkdir -p "$(dirname "$FILE_PATH")"

    if [ -f "$FILE_PATH" ]; then
        # Append to existing file with a blank separator
        printf '\n%s\n' "$CODE" >> "$FILE_PATH"
        echo "  Updated: $FILE_PATH ($TEST_NAME)"
    else
        printf '%s\n' "$CODE" > "$FILE_PATH"
        echo "  Created: $FILE_PATH ($TEST_NAME)"
    fi

    WRITTEN_FILES+=("$FILE_PATH")
done < <(echo "$FUNC_TESTS" | jq -c '.[]')

# ---------------------------------------------------------------------------
# Stage and commit
# ---------------------------------------------------------------------------
echo ""
echo "Staging files..."
# Stage unique file paths (a file may have had multiple tests appended)
echo "$FUNC_TESTS" | jq -r '.[].file_path' | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && git add "$f"
done

if git diff --cached --quiet; then
    echo "Nothing to commit — files may already be up to date."
    exit 0
fi

COMMIT_MSG=$(cat <<EOF
harness: functional tests for $ISSUE

Auto-generated functional tests from harness framework.
Source repo: $SOURCE_REPO_PATH

Tests require aap-dev environment to run.
See: make aap-test
EOF
)

git commit -m "$COMMIT_MSG"
echo "Committed $FUNC_TEST_COUNT functional test(s)."

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
echo ""
echo "Pushing $BRANCH to $REMOTE..."
git push -u "$REMOTE" "$BRANCH"

# ---------------------------------------------------------------------------
# Open PR
# ---------------------------------------------------------------------------
echo ""

TEST_LIST=$(echo "$FUNC_TESTS" | jq -r '.[] | "- `\(.test_name)` — \(.source_requirement // "see acceptance criteria")"')

PR_BODY=$(cat <<EOF
## Summary

Auto-generated functional tests for **$ISSUE**, created by the harness framework.

These tests require the **aap-dev** environment to run.

## Tests Added ($FUNC_TEST_COUNT)

$TEST_LIST

## Running the Tests

\`\`\`
make aap-test
\`\`\`

## Review Checklist

- [ ] Tests map to acceptance criteria in $ISSUE
- [ ] Assertions match expected behaviour
- [ ] Setup/teardown is appropriate for the aap-dev environment
- [ ] No hardcoded credentials or environment-specific values

---
*Generated by [harness](https://github.com/ansible-automation-platform/harness)*
EOF
)

if command -v gh &>/dev/null; then
    PR_URL=$(gh pr create \
        --title "Functional tests for $ISSUE" \
        --body "$PR_BODY" \
        --base "$DEFAULT_BRANCH" \
        --head "$BRANCH")
    echo "PR created: $PR_URL"
else
    echo "PR must be created manually:"
    echo "  Branch: $BRANCH"
    echo "  Base:   $DEFAULT_BRANCH"
    echo "  Remote: $REMOTE"
fi
