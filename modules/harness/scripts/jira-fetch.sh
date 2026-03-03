#!/bin/bash
# Fetch Jira context for the current issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"
CACHE_TTL="${HARNESS_CACHE_TTL:-1800}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" || echo "")

if [ -z "$ISSUE" ]; then
    echo "Error: Could not detect Jira issue" >&2
    echo "Set HARNESS_ISSUE or use a branch named like 'feature/PROJ-1234'" >&2
    exit 1
fi

echo "Issue: $ISSUE"

CACHE_FILE="$CACHE_DIR/jira-context-${ISSUE}.json"
CONFIG_HASH=$(echo "${HARNESS_JIRA_BASE_URL}${HARNESS_JIRA_PROJECT}" | md5sum | cut -c1-8 2>/dev/null || echo "nocache")
CACHE_KEY_FILE="$CACHE_DIR/.jira-cache-key-${ISSUE}"

# Check cache validity
if [ "$HARNESS_NO_CACHE" != "true" ] && [ -f "$CACHE_FILE" ] && [ -f "$CACHE_KEY_FILE" ]; then
    CACHED_KEY=$(cat "$CACHE_KEY_FILE")
    FILE_AGE=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))

    if [ "$CACHED_KEY" = "$CONFIG_HASH" ] && [ "$FILE_AGE" -lt "$CACHE_TTL" ]; then
        echo "Using cached Jira context (age: ${FILE_AGE}s)"
        exit 0
    fi
fi

# Validate credentials
if [ -z "$HARNESS_JIRA_EMAIL" ] || [ -z "$HARNESS_JIRA_API_TOKEN" ]; then
    echo "Warning: Jira credentials not configured" >&2
    echo "Creating placeholder context..."

    cat > "$CACHE_FILE" << EOF
{
  "issue": {
    "key": "$ISSUE",
    "summary": "[Jira not configured - placeholder]",
    "description": "Configure HARNESS_JIRA_EMAIL and HARNESS_JIRA_API_TOKEN in .harness.local.env",
    "type": "Story",
    "status": "Unknown",
    "acceptance_criteria": [],
    "labels": [],
    "custom_fields": {}
  },
  "epic": null,
  "linked_issues": [],
  "comments": [],
  "_meta": {
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "placeholder": true
  }
}
EOF
    exit 0
fi

AUTH="${HARNESS_JIRA_EMAIL}:${HARNESS_JIRA_API_TOKEN}"
BASE_URL="${HARNESS_JIRA_BASE_URL}"

echo "Fetching from Jira API..."

# Fetch issue details
ISSUE_RESPONSE=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/rest/api/3/issue/${ISSUE}?expand=renderedFields,changelog")

if echo "$ISSUE_RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
    ERROR=$(echo "$ISSUE_RESPONSE" | jq -r '.errorMessages[0] // "Unknown error"')
    echo "Error fetching issue: $ERROR" >&2
    exit 1
fi

# Extract fields
SUMMARY=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.summary // ""')
DESCRIPTION=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.description // ""')
ISSUE_TYPE=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.issuetype.name // "Unknown"')
STATUS=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.status.name // "Unknown"')
LABELS=$(echo "$ISSUE_RESPONSE" | jq '.fields.labels // []')
EPIC_KEY=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.parent.key // .fields.customfield_10014 // ""')

# Extract acceptance criteria (common custom field names)
AC=$(echo "$ISSUE_RESPONSE" | jq -r '
    .fields.customfield_10016 //
    .fields.customfield_10020 //
    .fields."Acceptance Criteria" //
    .renderedFields.customfield_10016 //
    ""
')

# Fetch comments
COMMENTS=$(curl -s -u "$AUTH" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/rest/api/3/issue/${ISSUE}/comment" | jq '[.comments[:10] | .[] | {author: .author.displayName, body: .body, created: .created}]')

# Fetch epic if present
EPIC_DATA="null"
if [ -n "$EPIC_KEY" ] && [ "$EPIC_KEY" != "null" ]; then
    echo "Fetching epic: $EPIC_KEY"
    EPIC_RESPONSE=$(curl -s -u "$AUTH" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/rest/api/3/issue/${EPIC_KEY}" 2>/dev/null || echo "{}")

    if ! echo "$EPIC_RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
        EPIC_SUMMARY=$(echo "$EPIC_RESPONSE" | jq -r '.fields.summary // ""')
        EPIC_DESC=$(echo "$EPIC_RESPONSE" | jq -r '.fields.description // ""')

        # Get child issues in epic
        CHILDREN=$(curl -s -u "$AUTH" \
            -H "Content-Type: application/json" \
            "${BASE_URL}/rest/api/3/search?jql=parent=${EPIC_KEY}&fields=key" | jq '[.issues[].key]')

        EPIC_DATA=$(jq -n \
            --arg key "$EPIC_KEY" \
            --arg summary "$EPIC_SUMMARY" \
            --arg desc "$EPIC_DESC" \
            --argjson children "$CHILDREN" \
            '{key: $key, summary: $summary, description: $desc, child_issues: $children}')
    fi
fi

# Fetch linked issues
LINKS=$(echo "$ISSUE_RESPONSE" | jq '[.fields.issuelinks // [] | .[] | {
    type: .type.name,
    direction: (if .inwardIssue then "inward" else "outward" end),
    key: (.inwardIssue.key // .outwardIssue.key),
    summary: (.inwardIssue.fields.summary // .outwardIssue.fields.summary)
}]')

# Build context document
jq -n \
    --arg key "$ISSUE" \
    --arg summary "$SUMMARY" \
    --arg description "$DESCRIPTION" \
    --arg type "$ISSUE_TYPE" \
    --arg status "$STATUS" \
    --arg ac "$AC" \
    --argjson labels "$LABELS" \
    --argjson epic "$EPIC_DATA" \
    --argjson links "$LINKS" \
    --argjson comments "$COMMENTS" \
    '{
        issue: {
            key: $key,
            summary: $summary,
            description: $description,
            type: $type,
            status: $status,
            acceptance_criteria: (if $ac != "" then [$ac] else [] end),
            labels: $labels,
            custom_fields: {}
        },
        epic: $epic,
        linked_issues: $links,
        comments: $comments,
        _meta: {
            fetched_at: (now | todate),
            placeholder: false
        }
    }' > "$CACHE_FILE"

# Save cache key
echo "$CONFIG_HASH" > "$CACHE_KEY_FILE"

echo "Jira context saved to $CACHE_FILE"
