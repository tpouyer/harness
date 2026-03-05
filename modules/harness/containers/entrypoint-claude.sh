#!/bin/bash
# Entrypoint for Claude agent container (via Google Cloud Vertex AI)
#
# Required environment variables:
#   GCP_PROJECT_ID              - Google Cloud project ID for Vertex AI
#
# Optional environment variables:
#   GCP_REGION                  - Google Cloud region (default: us-east5)
#   GCP_QUOTA_PROJECT           - Quota project for ADC (default: $GCP_PROJECT_ID)
#   GOOGLE_APPLICATION_CREDENTIALS - Path to service account key (for non-interactive auth)
#   HARNESS_AI_MODEL            - Claude model to use (default: claude-sonnet-4-5-20250514)

set -e

TASK="${1:-assist}"
CONTEXT_DIR="/workspace/.harness"

echo "Harness Claude Agent (Vertex AI)"
echo "Task: $TASK"
echo ""

# ── Validate configuration ──────────────────────────────────────────────────
if [ -z "$GCP_PROJECT_ID" ]; then
    echo "Error: GCP_PROJECT_ID must be set" >&2
    echo "  This is the Google Cloud project ID with Vertex AI + Claude enabled." >&2
    exit 1
fi

GCP_REGION="${GCP_REGION:-us-east5}"
GCP_QUOTA_PROJECT="${GCP_QUOTA_PROJECT:-$GCP_PROJECT_ID}"

# ── Google Cloud authentication ─────────────────────────────────────────────
# The init script (init-claude.sh) copies the mounted ADC file into
# ~/.config/gcloud/ as root before dropping to this user. We just need to
# configure gcloud to use it.
GCLOUD_DIR="/home/harness/.config/gcloud"

if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    echo "Authenticating with service account key..."
    gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --quiet
    gcloud config set project "$GCP_PROJECT_ID" --quiet
elif [ -f "$GCLOUD_DIR/application_default_credentials.json" ]; then
    echo "Using Application Default Credentials."
    gcloud config set project "$GCP_PROJECT_ID" --quiet
    gcloud auth application-default set-quota-project "$GCP_QUOTA_PROJECT" --quiet 2>/dev/null || true
else
    echo "Warning: No credentials found." >&2
    echo "  Mount your ADC file: -v ~/.config/gcloud/application_default_credentials.json:/tmp/adc.json:z" >&2
fi

# ── Export Vertex AI environment for Claude Code and Anthropic SDK ───────────
export CLAUDE_CODE_USE_VERTEX=1
export CLOUD_ML_REGION="$GCP_REGION"
export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT_ID"

echo "Project:  $GCP_PROJECT_ID"
echo "Region:   $GCP_REGION"
echo "Quota:    $GCP_QUOTA_PROJECT"
echo ""

# ── Check for prompt file ───────────────────────────────────────────────────
PROMPT_FILE="$CONTEXT_DIR/prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: Prompt file not found at $PROMPT_FILE" >&2
    exit 1
fi

# Read prompt
PROMPT=$(cat "$PROMPT_FILE")

# ── Execute agent task via Anthropic Vertex SDK ─────────────────────────────
python3 << 'PYEOF'
import os
import json
from anthropic import AnthropicVertex

project_id = os.environ["ANTHROPIC_VERTEX_PROJECT_ID"]
region = os.environ.get("CLOUD_ML_REGION", "us-east5")

client = AnthropicVertex(project_id=project_id, region=region)

with open(os.environ.get("PROMPT_FILE", "/workspace/.harness/prompt.md")) as f:
    prompt = f.read()

model = os.environ.get("HARNESS_AI_MODEL", "claude-sonnet-4-5-20250514")

response = client.messages.create(
    model=model,
    max_tokens=4096,
    messages=[
        {"role": "user", "content": prompt}
    ]
)

task = os.environ.get("TASK", "assist")
context_dir = os.environ.get("CONTEXT_DIR", "/workspace/.harness")

result = {
    "task": task,
    "provider": "claude-vertex",
    "model": response.model,
    "result": response.content[0].text,
    "usage": {
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens
    }
}

result_path = os.path.join(context_dir, "result.json")
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)

print(response.content[0].text)
PYEOF

echo ""
echo "Result saved to $CONTEXT_DIR/result.json"
