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
    # Strip surrounding quotes that Make's -include may preserve
    local TOKEN="${HARNESS_JIRA_API_TOKEN}"
    TOKEN="${TOKEN#\"}"
    TOKEN="${TOKEN%\"}"
    TOKEN="${TOKEN#\'}"
    TOKEN="${TOKEN%\'}"

    local EMAIL="${HARNESS_JIRA_EMAIL}"
    EMAIL="${EMAIL#\"}"
    EMAIL="${EMAIL%\"}"

    if [ "${HARNESS_JIRA_AUTH_TYPE:-auto}" = "bearer" ] || [ -z "$EMAIL" ]; then
        CURL_AUTH=(-H "Authorization: Bearer ${TOKEN}")
    else
        CURL_AUTH=(-u "${EMAIL}:${TOKEN}")
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

# Discover custom field IDs from Jira field metadata
# Sets PARENT_LINK_FIELD, EPIC_LINK_FIELD, and AC_FIELD
discover_hierarchy_fields() {
    # Allow explicit overrides
    if [ -n "${HARNESS_JIRA_PARENT_LINK_FIELD:-}" ]; then
        PARENT_LINK_FIELD="$HARNESS_JIRA_PARENT_LINK_FIELD"
    fi
    if [ -n "${HARNESS_JIRA_EPIC_LINK_FIELD:-}" ]; then
        EPIC_LINK_FIELD="$HARNESS_JIRA_EPIC_LINK_FIELD"
    fi
    if [ -n "${HARNESS_JIRA_AC_FIELD:-}" ]; then
        AC_FIELD="$HARNESS_JIRA_AC_FIELD"
    fi

    # Skip API call if all are already set
    if [ -n "${PARENT_LINK_FIELD:-}" ] && [ -n "${EPIC_LINK_FIELD:-}" ] && [ -n "${AC_FIELD:-}" ]; then
        echo "Using configured field overrides"
        return
    fi

    local FIELDS_RESPONSE
    FIELDS_RESPONSE=$(curl -s "${CURL_AUTH[@]}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}${API_PATH}/field" 2>/dev/null || echo "[]")

    if [ -z "${PARENT_LINK_FIELD:-}" ]; then
        PARENT_LINK_FIELD=$(echo "$FIELDS_RESPONSE" | jq -r '
            [.[] | select(.name == "Parent Link" and .custom == true)] | first | .id // ""
        ' 2>/dev/null || echo "")
    fi

    if [ -z "${EPIC_LINK_FIELD:-}" ]; then
        EPIC_LINK_FIELD=$(echo "$FIELDS_RESPONSE" | jq -r '
            [.[] | select(.name == "Epic Link" and .custom == true)] | first | .id // ""
        ' 2>/dev/null || echo "")
    fi

    if [ -z "${AC_FIELD:-}" ]; then
        AC_FIELD=$(echo "$FIELDS_RESPONSE" | jq -r '
            [.[] | select(.name == "Acceptance Criteria" and .custom == true)] | first | .id // ""
        ' 2>/dev/null || echo "")
    fi

    for name_val in "Parent Link:$PARENT_LINK_FIELD" "Epic Link:$EPIC_LINK_FIELD" "Acceptance Criteria:$AC_FIELD"; do
        local fname="${name_val%%:*}" fval="${name_val#*:}"
        if [ -n "$fval" ]; then
            echo "Discovered $fname field: $fval"
        fi
    done
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
# Uses discovered PARENT_LINK_FIELD and EPIC_LINK_FIELD plus standard fallbacks
get_parent_key() {
    local ISSUE_RESPONSE="$1"
    local PARENT_KEY=""

    # Try the dynamically discovered Parent Link field first
    if [ -n "${PARENT_LINK_FIELD:-}" ]; then
        PARENT_KEY=$(echo "$ISSUE_RESPONSE" | jq -r --arg f "$PARENT_LINK_FIELD" '
            .fields[$f] | if type == "object" then .key else . end // ""
        ' 2>/dev/null)
    fi

    # Try the dynamically discovered Epic Link field
    if [ -z "$PARENT_KEY" ] || [ "$PARENT_KEY" = "null" ]; then
        if [ -n "${EPIC_LINK_FIELD:-}" ]; then
            PARENT_KEY=$(echo "$ISSUE_RESPONSE" | jq -r --arg f "$EPIC_LINK_FIELD" '
                .fields[$f] | if type == "object" then .key else . end // ""
            ' 2>/dev/null)
        fi
    fi

    # Fall back to standard fields
    if [ -z "$PARENT_KEY" ] || [ "$PARENT_KEY" = "null" ]; then
        PARENT_KEY=$(echo "$ISSUE_RESPONSE" | jq -r '
            .fields.parent.key //
            .fields.customfield_10018.key //
            .fields.customfield_10014 //
            ""
        ' 2>/dev/null | head -1)
    fi

    echo "$PARENT_KEY"
}

# Extract acceptance criteria from an issue response
# Uses dynamically discovered AC_FIELD with standard fallbacks
extract_acceptance_criteria() {
    local ISSUE_RESPONSE="$1"
    local AC_VALUE=""

    # Try the dynamically discovered field first
    if [ -n "${AC_FIELD:-}" ]; then
        AC_VALUE=$(echo "$ISSUE_RESPONSE" | jq -r --arg f "$AC_FIELD" '
            .fields[$f] // ""
        ' 2>/dev/null)
    fi

    # Fall back to standard fields
    if [ -z "$AC_VALUE" ] || [ "$AC_VALUE" = "null" ]; then
        AC_VALUE=$(echo "$ISSUE_RESPONSE" | jq -r '
            .fields.customfield_10016 //
            .fields.customfield_10020 //
            .fields."Acceptance Criteria" //
            .renderedFields.customfield_10016 //
            ""
        ' 2>/dev/null)
    fi

    echo "$AC_VALUE"
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
        "Outcome"|"outcome") echo "outcome" ;;
        "Story"|"story"|"Task"|"task"|"Bug"|"bug"|"Sub-task"|"sub-task") echo "issue" ;;
        *) echo "$TYPE" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

# Call the GitHub API, preferring gh CLI (uses its own keyring auth) over curl+GITHUB_TOKEN.
# Note: GITHUB_TOKEN env var is unset for gh calls to prevent it from overriding
# gh's own auth with a potentially less-privileged token.
github_api() {
    local ENDPOINT="$1"
    if command -v gh &> /dev/null; then
        GITHUB_TOKEN= GH_TOKEN= gh api "$ENDPOINT" 2>/dev/null
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
            "https://api.github.com/${ENDPOINT}" 2>/dev/null
    else
        echo ""
    fi
}

# Fetch raw file content from GitHub, preferring gh CLI over curl
github_raw_fetch() {
    local RAW_URL="$1"
    if command -v gh &> /dev/null; then
        # Extract owner/repo/ref/path from raw URL and use gh api
        # https://raw.githubusercontent.com/owner/repo/ref/path
        local PARTS
        PARTS=$(echo "$RAW_URL" | sed -E 's|https://raw.githubusercontent.com/([^/]+)/([^/]+)/([^/]+)/(.+)|\1 \2 \3 \4|')
        local OWNER REPO REF FILEPATH
        OWNER=$(echo "$PARTS" | cut -d' ' -f1)
        REPO=$(echo "$PARTS" | cut -d' ' -f2)
        REF=$(echo "$PARTS" | cut -d' ' -f3)
        FILEPATH=$(echo "$PARTS" | cut -d' ' -f4-)
        # URL-encode the filepath (spaces, colons, etc.)
        local ENCODED_PATH
        ENCODED_PATH=$(printf '%s' "$FILEPATH" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe='/'))" 2>/dev/null || echo "$FILEPATH")
        GITHUB_TOKEN= GH_TOKEN= gh api "repos/${OWNER}/${REPO}/contents/${ENCODED_PATH}?ref=${REF}" \
            -H "Accept: application/vnd.github.raw+json" 2>/dev/null
    elif [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -s -L -H "Authorization: token ${GITHUB_TOKEN}" "$RAW_URL" 2>/dev/null
    else
        curl -s -L "$RAW_URL" 2>/dev/null
    fi
}

# Function to fetch GitHub raw content for handbook documents
# Handles both blob URLs and PR URLs
fetch_handbook_content() {
    local URL="$1"
    local CONTENT=""

    # Check if this is a PR URL (e.g. https://github.com/owner/repo/pull/123)
    if echo "$URL" | grep -qE 'github\.com/[^/]+/[^/]+/pull/[0-9]+'; then
        local OWNER REPO PR_NUM
        OWNER=$(echo "$URL" | sed -E 's|.*/([^/]+)/([^/]+)/pull/([0-9]+).*|\1|')
        REPO=$(echo "$URL" | sed -E 's|.*/([^/]+)/([^/]+)/pull/([0-9]+).*|\2|')
        PR_NUM=$(echo "$URL" | sed -E 's|.*/([^/]+)/([^/]+)/pull/([0-9]+).*|\3|')

        # Get the PR head commit SHA (works even after branch deletion on merged PRs)
        local PR_DATA HEAD_SHA
        PR_DATA=$(github_api "repos/${OWNER}/${REPO}/pulls/${PR_NUM}")
        HEAD_SHA=$(echo "$PR_DATA" | jq -r '.head.sha // ""' 2>/dev/null)

        if [ -z "$HEAD_SHA" ] || [ "$HEAD_SHA" = "null" ]; then
            echo "[Could not fetch PR #${PR_NUM} metadata from ${OWNER}/${REPO}]"
            return
        fi

        # Get the list of files changed in the PR, filter for markdown docs
        local PR_FILES MD_FILES
        PR_FILES=$(github_api "repos/${OWNER}/${REPO}/pulls/${PR_NUM}/files?per_page=50")
        MD_FILES=$(echo "$PR_FILES" | jq -r '[.[] | select(.filename | test("\\.(md|markdown)$"; "i")) | .filename] | .[]' 2>/dev/null)

        if [ -z "$MD_FILES" ]; then
            echo "[No markdown files found in PR #${PR_NUM}]"
            return
        fi

        # Fetch content of each markdown file from the PR's head commit
        local FILE RAW_URL FILE_CONTENT
        while IFS= read -r FILE; do
            [ -z "$FILE" ] && continue
            RAW_URL="https://raw.githubusercontent.com/${OWNER}/${REPO}/${HEAD_SHA}/${FILE}"
            FILE_CONTENT=$(github_raw_fetch "$RAW_URL" | head -c 10000 || echo "")

            if [ -n "$FILE_CONTENT" ]; then
                if [ -n "$CONTENT" ]; then
                    CONTENT="${CONTENT}"$'\n\n---\n\n'
                fi
                CONTENT="${CONTENT}# ${FILE}"$'\n\n'"${FILE_CONTENT}"
            fi
        done <<< "$MD_FILES"

        if [ -n "$CONTENT" ]; then
            echo "$CONTENT"
        else
            echo "[Could not fetch content from PR #${PR_NUM}]"
        fi
    else
        # Standard blob URL: convert to raw URL
        local RAW_URL
        RAW_URL=$(echo "$URL" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|/blob/|/|')

        CONTENT=$(github_raw_fetch "$RAW_URL" | head -c 10000 || echo "")

        if [ -n "$CONTENT" ]; then
            echo "$CONTENT"
        else
            echo "[Could not fetch content from $URL]"
        fi
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

        local SUMMARY TYPE STATUS DESCRIPTION AC
        SUMMARY=$(echo "$RESPONSE" | jq -r '.fields.summary // ""')
        TYPE=$(get_hierarchy_type "$RESPONSE")
        STATUS=$(echo "$RESPONSE" | jq -r '.fields.status.name // "Unknown"')
        DESCRIPTION=$(echo "$RESPONSE" | jq -r '.fields.description // ""')
        AC=$(extract_acceptance_criteria "$RESPONSE")

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
            --arg ac "$AC" \
            '. + [{key: $key, type: $type, summary: $summary, status: $status, description: $desc, acceptance_criteria: (if $ac != "" then $ac else null end)}]')

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
discover_hierarchy_fields

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
EPIC_KEY=$(get_parent_key "$ISSUE_RESPONSE")

# Extract acceptance criteria
AC=$(extract_acceptance_criteria "$ISSUE_RESPONSE")

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
