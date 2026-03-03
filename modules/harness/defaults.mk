# Harness Module Defaults
# These values can be overridden in .harness/config.env or .harness.local.env

# Jira Configuration
export HARNESS_JIRA_BASE_URL ?= https://your-company.atlassian.net
export HARNESS_JIRA_PROJECT ?= PROJ
export HARNESS_JIRA_EMAIL ?=
export HARNESS_JIRA_API_TOKEN ?=
export HARNESS_BRANCH_PATTERN ?= ([A-Z]+-[0-9]+)

# AI Provider Configuration
export HARNESS_AI_PROVIDER ?= claude
export HARNESS_AI_API_KEY ?=
export HARNESS_AI_MODEL ?= claude-sonnet-4-5-20250514
export HARNESS_AI_FALLBACK ?= openai,local

# Per-capability provider routing (optional)
export HARNESS_PROVIDER_INTENT ?= $(HARNESS_AI_PROVIDER)
export HARNESS_PROVIDER_TESTS ?= $(HARNESS_AI_PROVIDER)
export HARNESS_PROVIDER_ASSIST ?= $(HARNESS_AI_PROVIDER)
export HARNESS_PROVIDER_DISCOVERY ?= local

# Paude Configuration
export HARNESS_PAUDE_BACKEND ?= podman
export HARNESS_PAUDE_ALLOWED_DOMAINS ?= api.anthropic.com,api.openai.com,*.atlassian.net
export HARNESS_CONTAINER_REGISTRY ?= ghcr.io/your-org

# Cache Configuration
export HARNESS_CACHE_TTL ?= 1800
export HARNESS_NO_CACHE ?= false

# Output Configuration
export HARNESS_OUTPUT_FORMAT ?= markdown
export HARNESS_DRY_RUN ?= false

# Language/Framework Configuration
export HARNESS_LANGUAGE ?= auto
export HARNESS_TEST_FRAMEWORK ?= auto

# Context limits
export HARNESS_MAX_CONTEXT_TOKENS ?= 100000
export HARNESS_MAX_FILES ?= 50
