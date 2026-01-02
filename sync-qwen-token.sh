#!/bin/bash
# sync-qwen-token.sh - Sync qwen-cli OAuth token to live-SWE-agent config
# Usage: ~/sync-qwen-token.sh

set -e

QWEN_CREDS="$HOME/.qwen/oauth_creds.json"
SWE_ENV="$HOME/.config/mini-swe-agent/.env"

# Check if qwen credentials exist
if [ ! -f "$QWEN_CREDS" ]; then
    echo "❌ Error: qwen-cli credentials not found at $QWEN_CREDS"
    echo "   Run qwen on a machine with a browser to authenticate first."
    exit 1
fi

# Extract the access token using python
NEW_TOKEN=$(python3 << PYEOF
import json
with open("$QWEN_CREDS") as f:
    data = json.load(f)
    print(data["access_token"])
PYEOF
)

if [ -z "$NEW_TOKEN" ]; then
    echo "❌ Error: Could not extract access_token from $QWEN_CREDS"
    exit 1
fi

# Check if live-SWE-agent config exists
if [ ! -f "$SWE_ENV" ]; then
    echo "⚠️  live-SWE-agent config not found. Creating new one..."
    mkdir -p "$(dirname "$SWE_ENV")"
    cat > "$SWE_ENV" << ENVEOF
OPENAI_API_KEY=$NEW_TOKEN
OPENAI_BASE_URL=https://portal.qwen.ai/v1
MSWEA_MODEL_NAME=openai/qwen3-coder-plus
MSWEA_CONFIGURED=true
MSWEA_COST_TRACKING=ignore_errors
ENVEOF
    echo "✅ Created new config at $SWE_ENV"
else
    # Update existing config
    OLD_TOKEN=$(grep "^OPENAI_API_KEY=" "$SWE_ENV" | cut -d= -f2)
    
    if [ "$OLD_TOKEN" = "$NEW_TOKEN" ]; then
        echo "✅ Token is already up to date. No changes needed."
        exit 0
    fi
    
    sed -i "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$NEW_TOKEN|" "$SWE_ENV"
    echo "✅ Token updated successfully!"
    echo "   Old: ${OLD_TOKEN:0:20}..."
    echo "   New: ${NEW_TOKEN:0:20}..."
fi

# Verify the token works
echo ""
echo "🔍 Testing token validity..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://portal.qwen.ai/v1/chat/completions" \
    -H "Authorization: Bearer $NEW_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"qwen3-coder-plus\", \"messages\": [{\"role\": \"user\", \"content\": \"hi\"}], \"max_tokens\": 5}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Token is valid! API responded successfully."
else
    echo "❌ Token validation failed! HTTP code: $HTTP_CODE"
    echo "   Response: $BODY"
    exit 1
fi
