#!/bin/bash
# Estimate token costs for harness operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${HARNESS_CACHE_DIR:-.harness/.cache}"

# Token pricing (per 1M tokens, approximate)
declare -A INPUT_COSTS
declare -A OUTPUT_COSTS

INPUT_COSTS[claude]=3.00
OUTPUT_COSTS[claude]=15.00
INPUT_COSTS[openai]=2.50
OUTPUT_COSTS[openai]=10.00
INPUT_COSTS[local]=0.00
OUTPUT_COSTS[local]=0.00

PROVIDER="${HARNESS_AI_PROVIDER:-claude}"

# Detect issue
ISSUE=$("$SCRIPT_DIR/detect-issue.sh" 2>/dev/null || echo "unknown")

# Calculate context sizes
JIRA_TOKENS=0
CODE_TOKENS=0

if [ -f "$CACHE_DIR/jira-context-${ISSUE}.json" ]; then
    JIRA_SIZE=$(wc -c < "$CACHE_DIR/jira-context-${ISSUE}.json")
    JIRA_TOKENS=$((JIRA_SIZE / 4))  # Rough estimate: 4 chars per token
fi

if [ -f "$CACHE_DIR/code-context-${ISSUE}.json" ]; then
    CODE_SIZE=$(wc -c < "$CACHE_DIR/code-context-${ISSUE}.json")
    CODE_TOKENS=$((CODE_SIZE / 4))
fi

# Estimate prompt overhead
PROMPT_OVERHEAD=2000

# Estimate output sizes per task
declare -A OUTPUT_ESTIMATES
OUTPUT_ESTIMATES[intent-check]=2000
OUTPUT_ESTIMATES[suggest-tests]=4000
OUTPUT_ESTIMATES[find-tests]=1000
OUTPUT_ESTIMATES[assist]=2000

echo "Token Cost Estimate"
echo "==================="
echo ""
echo "Provider: $PROVIDER"
echo "Issue: $ISSUE"
echo ""
echo "Context Sizes:"
echo "  Jira context: ~$JIRA_TOKENS tokens"
echo "  Code context: ~$CODE_TOKENS tokens"
echo "  Prompt overhead: ~$PROMPT_OVERHEAD tokens"
echo ""

TOTAL_INPUT=$((JIRA_TOKENS + CODE_TOKENS + PROMPT_OVERHEAD))
echo "Total input: ~$TOTAL_INPUT tokens"
echo ""

INPUT_RATE=${INPUT_COSTS[$PROVIDER]:-3.00}
OUTPUT_RATE=${OUTPUT_COSTS[$PROVIDER]:-15.00}

echo "Estimated Costs per Task:"
echo ""

for task in intent-check suggest-tests find-tests assist; do
    OUTPUT_EST=${OUTPUT_ESTIMATES[$task]}

    INPUT_COST=$(echo "scale=4; $TOTAL_INPUT * $INPUT_RATE / 1000000" | bc)
    OUTPUT_COST=$(echo "scale=4; $OUTPUT_EST * $OUTPUT_RATE / 1000000" | bc)
    TOTAL_COST=$(echo "scale=4; $INPUT_COST + $OUTPUT_COST" | bc)

    printf "  %-20s \$%.4f (in: \$%.4f, out: \$%.4f)\n" "$task" "$TOTAL_COST" "$INPUT_COST" "$OUTPUT_COST"
done

echo ""
echo "Daily estimate (20 calls): \$$(echo "scale=2; 20 * 0.10" | bc)"
echo "Monthly estimate: \$$(echo "scale=2; 20 * 22 * 0.10" | bc)"
