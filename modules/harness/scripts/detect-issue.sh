#!/bin/bash
# Detect Jira issue from git branch or explicit override

set -e

# Priority 1: Explicit override
if [ -n "$HARNESS_ISSUE" ]; then
    echo "$HARNESS_ISSUE"
    exit 0
fi

BRANCH_PATTERN="${HARNESS_BRANCH_PATTERN:-([A-Z]+-[0-9]+)}"

# Priority 2: Git branch name
if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

    if [ -n "$BRANCH" ]; then
        # Extract issue key using pattern
        ISSUE=$(echo "$BRANCH" | grep -oE "$BRANCH_PATTERN" | head -1 || true)

        if [ -n "$ISSUE" ]; then
            echo "$ISSUE"
            exit 0
        fi
    fi

    # Priority 3: Recent commit messages
    COMMITS=$(git log --oneline -5 2>/dev/null || echo "")
    if [ -n "$COMMITS" ]; then
        ISSUE=$(echo "$COMMITS" | grep -oE "$BRANCH_PATTERN" | head -1 || true)

        if [ -n "$ISSUE" ]; then
            echo "$ISSUE"
            exit 0
        fi
    fi
fi

# No issue found
echo ""
exit 1
