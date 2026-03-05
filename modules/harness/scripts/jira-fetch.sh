#!/bin/bash
# Fetch Jira context for the current issue

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"
CACHE_TTL="${HARNESS_CACHE_TTL:-1800}"
HANDBOOK_REPO="https://github.com/ansible/handbook"

# Build curl auth args based on auth type (bearer vs basic)
# Sets CURL_AUTH as an array to be used in curl calls
setup_auth() {
    if [ "${HARNESS_JIRA_AUTH_TYPE:-auto}" = "bearer" ] || [ -z "$HARNESS_JIRA_EMAIL" ]; then
        CURL_AUTH=(-H "Authorization: Bearer ${HARNESS_JIRA_API_TOKEN}")
    else
        CURL_AUTH=(-u "${HARNESS_JIRA_EMAIL}:${HARNESS_JIRA_API_TOKEN}")
    fi
}

# Detect the Jira REST API version (v3 for Cloud, v2 for Server/DC)
# Sets API_PATH to the base API path (e.g. /rest/api/2 or /rest/api/3)
detect_api_version() {
    local base="$1"

    # Allow explicit override
    if [ -n "${HARNESS_JIRA_API_VERSION:-}" ]; then
        API_PATH="/rest/api/${HARNESS_JIRA_API_VERSION}"
        echo "Using configured API version: $API_PATH"
        return
    fi

    # Try v3 first (Jira Cloud)
    local v3_status
    v3_status=$(curl -s -o /dev/null -w "%{http_code}" "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${base}/rest/api/3/myself" 2>/dev/null || echo "000")

    if [ "$v3_status" = "200" ]; then
        API_PATH="/rest/api/3"
        echo "Detected Jira Cloud (API v3)"
        return
    fi

    # Fall back to v2 (Jira Server/Data Center)
    local v2_status
    v2_status=$(curl -s -o /dev/null -w "%{http_code}" "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${base}/rest/api/2/myself" 2>/dev/null || echo "000")

    if [ "$v2_status" = "200" ]; then
        API_PATH="/rest/api/2"
        echo "Detected Jira Server/DC (API v2)"
        return
    fi

    # Default to v2 and let downstream errors surface
    API_PATH="/rest/api/2"
    echo "Warning: Could not detect Jira API version (v3: $v3_status, v2: $v2_status). Defaulting to v2." >&2
    echo "  Check your credentials and HARNESS_JIRA_BASE_URL." >&2
}

# Function to fetch a Jira issue by key
fetch_issue() {
    local ISSUE_KEY="$1"
    curl -s "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}${API_PATH}/issue/${ISSUE_KEY}?expand=renderedFields" 2>/dev/null || echo "{}"
}

# Function to extract web links from an issue that match the handbook repo
extract_handbook_links() {
    local ISSUE_KEY="$1"
    local LINKS_RESPONSE

    # Fetch remote links (web links) for the issue
    LINKS_RESPONSE=$(curl -s "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}${API_PATH}/issue/${ISSUE_KEY}/remotelink" 2>/dev/null || echo "[]")

    # Filter for handbook links and extract relevant info
    echo "$LINKS_RESPONSE" | jq --arg repo "$HANDBOOK_REPO" '[
        .[] | select(.object.url | startswith($repo)) | {
            title: .object.title,
            url: .object.url,
            summary: .object.summary,
            source_issue: "'"$ISSUE_KEY"'"
        }
    ]' 2>/dev/null || echo "[]"
}

# Function to get parent issue key (for Feature/Initiative hierarchy)
get_parent_key() {
    local ISSUE_RESPONSE="$1"
    # Check multiple fields for parent relationship
    # parent field (for subtasks/stories in epics)
    # customfield_10014 is common for Epic Link
    # customfield_10018 is common for Parent Link in Jira Software
    echo "$ISSUE_RESPONSE" | jq -r '
        .fields.parent.key //
        .fields.customfield_10018.key //
        .fields.customfield_10014 //
        ""
    ' 2>/dev/null | head -1
}

# Function to determine issue hierarchy type
get_hierarchy_type() {
    local ISSUE_RESPONSE="$1"
    local TYPE
    TYPE=$(echo "$ISSUE_RESPONSE" | jq -r '.fields.issuetype.name // "Unknown"')

    # Normalize common types
    case "$TYPE" in
        "Epic"|"epic") echo "epic" ;;
        "Feature"|"feature") echo "feature" ;;
        "Initiative"|"initiative") echo "initiative" ;;
        "Story"|"story"|"Task"|"task"|"Bug"|"bug"|"Sub-task"|"sub-task") echo "issue" ;;
        *) echo "$TYPE" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

# Function to fetch GitHub raw content for handbook documents
fetch_handbook_content() {
    local URL="$1"
    local RAW_URL
    local CONTENT

    # Convert GitHub URL to raw URL
    # https://github.com/ansible/handbook/blob/main/path/to/file.md
    # becomes https://raw.githubusercontent.com/ansible/handbook/main/path/to/file.md
    RAW_URL=$(echo "$URL" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|/blob/|/|')

    # Fetch content (limit to first 10000 chars to avoid huge docs)
    CONTENT=$(curl -s -L "$RAW_URL" 2>/dev/null | head -c 10000 || echo "")

    if [ -n "$CONTENT" ]; then
        echo "$CONTENT"
    else
        echo "[Could not fetch content from $URL]"
    fi
}

# Function to traverse and build full hierarchy
build_hierarchy() {
    local CURRENT_KEY="$1"
    local MAX_DEPTH=5
    local DEPTH=0
    local HIERARCHY="[]"
    local ALL_HANDBOOK_LINKS="[]"

    while [ -n "$CURRENT_KEY" ] && [ "$CURRENT_KEY" != "null" ] && [ $DEPTH -lt $MAX_DEPTH ]; do
        echo "  Fetching hierarchy level $DEPTH: $CURRENT_KEY" >&2

        local RESPONSE
        RESPONSE=$(fetch_issue "$CURRENT_KEY")

        if echo "$RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
            break
        fi

        local SUMMARY TYPE STATUS DESCRIPTION
        SUMMARY=$(echo "$RESPONSE" | jq -r '.fields.summary // ""')
        TYPE=$(get_hierarchy_type "$RESPONSE")
        STATUS=$(echo "$RESPONSE" | jq -r '.fields.status.name // "Unknown"')
        DESCRIPTION=$(echo "$RESPONSE" | jq -r '.fields.description // ""')

        # Extract handbook links from this level
        local LEVEL_LINKS
        LEVEL_LINKS=$(extract_handbook_links "$CURRENT_KEY")

        # Merge into all handbook links
        ALL_HANDBOOK_LINKS=$(echo "$ALL_HANDBOOK_LINKS" "$LEVEL_LINKS" | jq -s 'add')

        # Add to hierarchy
        HIERARCHY=$(echo "$HIERARCHY" | jq --arg key "$CURRENT_KEY" \
            --arg summary "$SUMMARY" \
            --arg type "$TYPE" \
            --arg status "$STATUS" \
            --arg desc "$DESCRIPTION" \
            '. + [{key: $key, type: $type, summary: $summary, status: $status, description: $desc}]')

        # Get parent for next iteration
        CURRENT_KEY=$(get_parent_key "$RESPONSE")
        DEPTH=$((DEPTH + 1))
    done

    # Return both hierarchy and links as JSON
    jq -n --argjson hierarchy "$HIERARCHY" --argjson links "$ALL_HANDBOOK_LINKS" \
        '{hierarchy: $hierarchy, handbook_links: $links}'
}

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
if [ -z "$HARNESS_JIRA_API_TOKEN" ]; then
    echo "Warning: Jira credentials not configured (HARNESS_JIRA_API_TOKEN not set)" >&2
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
  "hierarchy": [],
  "handbook_documents": {
    "links": [],
    "documents": []
  },
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

BASE_URL="${HARNESS_JIRA_BASE_URL}"
setup_auth
detect_api_version "$BASE_URL"

echo "Fetching from Jira API..."

# Fetch issue details
ISSUE_RESPONSE=$(curl -s "${CURL_AUTH[@]}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}${API_PATH}/issue/${ISSUE}?expand=renderedFields,changelog")

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
COMMENTS=$(curl -s "${CURL_AUTH[@]}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}${API_PATH}/issue/${ISSUE}/comment" | jq '[.comments[:10] | .[] | {author: .author.displayName, body: .body, created: .created}]')

# Fetch epic if present
EPIC_DATA="null"
if [ -n "$EPIC_KEY" ] && [ "$EPIC_KEY" != "null" ]; then
    echo "Fetching epic: $EPIC_KEY"
    EPIC_RESPONSE=$(curl -s "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}${API_PATH}/issue/${EPIC_KEY}" 2>/dev/null || echo "{}")

    if ! echo "$EPIC_RESPONSE" | jq -e '.errorMessages' > /dev/null 2>&1; then
        EPIC_SUMMARY=$(echo "$EPIC_RESPONSE" | jq -r '.fields.summary // ""')
        EPIC_DESC=$(echo "$EPIC_RESPONSE" | jq -r '.fields.description // ""')

        # Get child issues in epic
        CHILDREN=$(curl -s "${CURL_AUTH[@]}" \
            -H "Content-Type: application/json" \
            "${BASE_URL}${API_PATH}/search?jql=parent=${EPIC_KEY}&fields=key" | jq '[.issues[].key]')

        EPIC_DATA=$(jq -n \
            --arg key "$EPIC_KEY" \
            --arg summary "$EPIC_SUMMARY" \
            --arg desc "$EPIC_DESC" \
            --argjson children "$CHILDREN" \
            '{key: $key, summary: $summary, description: $desc, child_issues: $children}')
    fi
fi

# Build full hierarchy (Epic → Feature → Initiative) and collect handbook links
FULL_HIERARCHY="[]"
HANDBOOK_LINKS="[]"
if [ -n "$EPIC_KEY" ] && [ "$EPIC_KEY" != "null" ]; then
    echo "Building issue hierarchy..."
    HIERARCHY_DATA=$(build_hierarchy "$EPIC_KEY")
    FULL_HIERARCHY=$(echo "$HIERARCHY_DATA" | jq '.hierarchy // []')
    HANDBOOK_LINKS=$(echo "$HIERARCHY_DATA" | jq '.handbook_links // []')
fi

# Also get handbook links from the current issue itself
ISSUE_HANDBOOK_LINKS=$(extract_handbook_links "$ISSUE")
HANDBOOK_LINKS=$(echo "$HANDBOOK_LINKS" "$ISSUE_HANDBOOK_LINKS" | jq -s 'add | unique_by(.url)')

# Fetch content for handbook documents (SDP/Proposals)
HANDBOOK_DOCS="[]"
LINK_COUNT=$(echo "$HANDBOOK_LINKS" | jq 'length' 2>/dev/null || echo "0")
LINK_COUNT=${LINK_COUNT:-0}
if [ "$LINK_COUNT" -gt 0 ]; then
    echo "Found $LINK_COUNT handbook link(s), fetching content..."

    # Calculate max index (limit to 5)
    MAX_INDEX=$((LINK_COUNT > 5 ? 4 : LINK_COUNT - 1))

    # Process each link
    for i in $(seq 0 "$MAX_INDEX"); do
        LINK_URL=$(echo "$HANDBOOK_LINKS" | jq -r ".[$i].url")
        LINK_TITLE=$(echo "$HANDBOOK_LINKS" | jq -r ".[$i].title // \"Document\"")
        SOURCE_ISSUE=$(echo "$HANDBOOK_LINKS" | jq -r ".[$i].source_issue")

        echo "  Fetching: $LINK_TITLE"
        CONTENT=$(fetch_handbook_content "$LINK_URL")

        # Determine document type from path
        DOC_TYPE="unknown"
        if echo "$LINK_URL" | grep -qi "sdp"; then
            DOC_TYPE="sdp"
        elif echo "$LINK_URL" | grep -qi "proposal"; then
            DOC_TYPE="proposal"
        elif echo "$LINK_URL" | grep -qi "rfc"; then
            DOC_TYPE="rfc"
        elif echo "$LINK_URL" | grep -qi "adr"; then
            DOC_TYPE="adr"
        fi

        HANDBOOK_DOCS=$(echo "$HANDBOOK_DOCS" | jq --arg url "$LINK_URL" \
            --arg title "$LINK_TITLE" \
            --arg type "$DOC_TYPE" \
            --arg source "$SOURCE_ISSUE" \
            --arg content "$CONTENT" \
            '. + [{url: $url, title: $title, type: $type, source_issue: $source, content: $content}]')
    done
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
    --argjson hierarchy "$FULL_HIERARCHY" \
    --argjson handbook_links "$HANDBOOK_LINKS" \
    --argjson handbook_docs "$HANDBOOK_DOCS" \
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
        hierarchy: $hierarchy,
        handbook_documents: {
            links: $handbook_links,
            documents: $handbook_docs
        },
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
