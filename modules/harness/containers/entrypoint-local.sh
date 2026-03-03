#!/bin/bash
# Entrypoint for Local (Ollama) agent container

set -e

TASK="${1:-assist}"
CONTEXT_DIR="/workspace/.harness"
MODEL="${HARNESS_AI_MODEL:-llama3.2}"

echo "Harness Local Agent (Ollama)"
echo "Task: $TASK"
echo "Model: $MODEL"
echo ""

# Start Ollama server if not running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Starting Ollama server..."
    ollama serve &
    sleep 5
fi

# Pull model if not available
if ! ollama list | grep -q "$MODEL"; then
    echo "Pulling model: $MODEL"
    ollama pull "$MODEL"
fi

# Check for prompt file
PROMPT_FILE="$CONTEXT_DIR/prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: Prompt file not found at $PROMPT_FILE" >&2
    exit 1
fi

# Read prompt
PROMPT=$(cat "$PROMPT_FILE")

# Execute via Ollama API
RESPONSE=$(curl -s http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL\",
        \"prompt\": $(echo "$PROMPT" | jq -Rs .),
        \"stream\": false
    }")

# Extract response
RESULT=$(echo "$RESPONSE" | jq -r '.response // empty')

if [ -z "$RESULT" ]; then
    echo "Error: No response from Ollama" >&2
    echo "Response: $RESPONSE" >&2
    exit 1
fi

# Save result
cat > "$CONTEXT_DIR/result.json" << EOF
{
    "task": "$TASK",
    "provider": "local",
    "model": "$MODEL",
    "result": $(echo "$RESULT" | jq -Rs .),
    "usage": {
        "input_tokens": 0,
        "output_tokens": 0
    }
}
EOF

echo "$RESULT"
echo ""
echo "Result saved to $CONTEXT_DIR/result.json"
