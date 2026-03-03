#!/bin/bash
# Entrypoint for Google Vertex AI agent container

set -e

TASK="${1:-assist}"
CONTEXT_DIR="/workspace/.harness"

echo "Harness Vertex AI Agent"
echo "Task: $TASK"
echo ""

# Validate credentials
if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ] && [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Error: GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_CLOUD_PROJECT must be set" >&2
    exit 1
fi

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
import vertexai
from vertexai.generative_models import GenerativeModel

project = os.environ.get("GOOGLE_CLOUD_PROJECT")
location = os.environ.get("GOOGLE_CLOUD_LOCATION", "us-central1")

vertexai.init(project=project, location=location)

model_name = os.environ.get("HARNESS_AI_MODEL", "gemini-1.5-pro")
model = GenerativeModel(model_name)

prompt = """${PROMPT}"""

response = model.generate_content(prompt)

result = {
    "task": "${TASK}",
    "provider": "vertex",
    "model": model_name,
    "result": response.text,
    "usage": {
        "input_tokens": response.usage_metadata.prompt_token_count if hasattr(response, 'usage_metadata') else 0,
        "output_tokens": response.usage_metadata.candidates_token_count if hasattr(response, 'usage_metadata') else 0
    }
}

with open("$CONTEXT_DIR/result.json", "w") as f:
    json.dump(result, f, indent=2)

print(response.text)
EOF

echo ""
echo "Result saved to $CONTEXT_DIR/result.json"
