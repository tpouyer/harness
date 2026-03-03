#!/bin/bash
# Entrypoint for OpenAI agent container

set -e

TASK="${1:-assist}"
CONTEXT_DIR="/workspace/.harness"

echo "Harness OpenAI Agent"
echo "Task: $TASK"
echo ""

# Validate API key
if [ -z "$OPENAI_API_KEY" ] && [ -z "$HARNESS_AI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY or HARNESS_AI_API_KEY must be set" >&2
    exit 1
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-$HARNESS_AI_API_KEY}"

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
from openai import OpenAI

client = OpenAI()

prompt = """${PROMPT}"""

response = client.chat.completions.create(
    model=os.environ.get("HARNESS_AI_MODEL", "gpt-4-turbo-preview"),
    max_tokens=4096,
    messages=[
        {"role": "user", "content": prompt}
    ]
)

result = {
    "task": "${TASK}",
    "provider": "openai",
    "model": response.model,
    "result": response.choices[0].message.content,
    "usage": {
        "input_tokens": response.usage.prompt_tokens,
        "output_tokens": response.usage.completion_tokens
    }
}

with open("$CONTEXT_DIR/result.json", "w") as f:
    json.dump(result, f, indent=2)

print(response.choices[0].message.content)
EOF

echo ""
echo "Result saved to $CONTEXT_DIR/result.json"
