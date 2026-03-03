#!/bin/bash
# Entrypoint for Claude agent container

set -e

TASK="${1:-assist}"
CONTEXT_DIR="/workspace/.harness"

echo "Harness Claude Agent"
echo "Task: $TASK"
echo ""

# Validate API key
if [ -z "$ANTHROPIC_API_KEY" ] && [ -z "$HARNESS_AI_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY or HARNESS_AI_API_KEY must be set" >&2
    exit 1
fi

export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-$HARNESS_AI_API_KEY}"

# Check for prompt file
PROMPT_FILE="$CONTEXT_DIR/prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: Prompt file not found at $PROMPT_FILE" >&2
    exit 1
fi

# Read prompt
PROMPT=$(cat "$PROMPT_FILE")

# Execute agent task
python3 << EOF
import os
import json
from anthropic import Anthropic

client = Anthropic()

prompt = """${PROMPT}"""

response = client.messages.create(
    model=os.environ.get("HARNESS_AI_MODEL", "claude-sonnet-4-5-20250514"),
    max_tokens=4096,
    messages=[
        {"role": "user", "content": prompt}
    ]
)

result = {
    "task": "${TASK}",
    "provider": "claude",
    "model": response.model,
    "result": response.content[0].text,
    "usage": {
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens
    }
}

with open("$CONTEXT_DIR/result.json", "w") as f:
    json.dump(result, f, indent=2)

print(response.content[0].text)
EOF

echo ""
echo "Result saved to $CONTEXT_DIR/result.json"
