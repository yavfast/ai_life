#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
OPENROUTER_BASE_URL="https://openrouter.ai/api/v1"
DEFAULT_MODEL="arcee-ai/trinity-large-preview:free"
API_KEY="${1:-}"

if [ -z "$API_KEY" ]; then
    echo "Get your API key from: https://openrouter.ai/keys"
    read -r -s -p "Enter your OpenRouter API key: " API_KEY
    echo
fi

if [ -z "$API_KEY" ]; then
    echo "No API key provided" >&2
    exit 1
fi

RESPONSE=$(curl -s -w "\n%{http_code}" -m 30 -X POST "${OPENROUTER_BASE_URL}/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -H "HTTP-Referer: https://github.com/yavfast/ai_life" \
    -H "X-Title: ai_life" \
    -d "{\"model\": \"$DEFAULT_MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"Reply with the word ready.\"}], \"max_tokens\": 8}" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" != "200" ]; then
    echo "OpenRouter key validation failed (HTTP $HTTP_CODE)" >&2
    echo "$BODY" >&2
    exit 1
fi

cat > "$ENV_FILE" <<EOF
OPENROUTER_API_KEY="$API_KEY"
OPENROUTER_API_BASE="$OPENROUTER_BASE_URL"
AI_LIFE_DEFAULT_MODEL="$DEFAULT_MODEL"
EOF

echo "Saved OpenRouter configuration to $ENV_FILE"
