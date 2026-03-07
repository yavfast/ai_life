#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_HOME="$HOME/.ai_life"
TARGET_GENERATION=""
MESSAGE_TEXT=""
METHOD="openrouter"
TIMEOUT_SECONDS=180

usage() {
    cat <<EOF
Usage: $0 [--home PATH] [--generation NAME] [--method METHOD] [message]

If message is omitted, it is read from stdin.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --home)
            RUNTIME_HOME="$2"
            shift 2
            ;;
        --generation)
            TARGET_GENERATION="$2"
            shift 2
            ;;
        --method)
            METHOD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "$MESSAGE_TEXT" ]; then
                MESSAGE_TEXT="$1"
            else
                MESSAGE_TEXT="$MESSAGE_TEXT $1"
            fi
            shift
            ;;
    esac
done

ACTIVE_FILE="$RUNTIME_HOME/state/active_generations.txt"

if [ -z "$TARGET_GENERATION" ]; then
    if [ ! -f "$ACTIVE_FILE" ]; then
        echo "Runtime home is not initialized: $RUNTIME_HOME" >&2
        exit 1
    fi
    TARGET_GENERATION=$(grep -v '^[[:space:]]*#' "$ACTIVE_FILE" | sed '/^[[:space:]]*$/d' | head -1)
fi

if [ -z "$MESSAGE_TEXT" ]; then
    MESSAGE_TEXT=$(cat)
fi

if [ -z "$MESSAGE_TEXT" ]; then
    echo "Message is empty" >&2
    exit 1
fi

INBOX_DIR="$RUNTIME_HOME/$TARGET_GENERATION/ai_home/state/inbox"
mkdir -p "$INBOX_DIR"
MESSAGE_ID="user-$(date +%Y%m%d-%H%M%S)-$$"
MESSAGE_FILE="$INBOX_DIR/$MESSAGE_ID.json"

python3 - <<'PY' "$MESSAGE_FILE" "$MESSAGE_ID" "$MESSAGE_TEXT"
from pathlib import Path
import json
import sys
from datetime import datetime, timezone

message_file = Path(sys.argv[1])
message_id = sys.argv[2]
message_text = sys.argv[3]
message = {
    "id": message_id,
    "from": "user",
    "created_at": datetime.now(timezone.utc).isoformat(),
    "status": "pending",
    "content": message_text,
    "response": "",
    "responded_at": ""
}
message_file.write_text(json.dumps(message, ensure_ascii=True, indent=2) + "\n")
PY

"$ROOT_DIR/run_ai.sh" --home "$RUNTIME_HOME" --only "$TARGET_GENERATION" "$METHOD"

START_TS=$(date +%s)
while true; do
    RESPONSE=$(python3 - <<'PY' "$MESSAGE_FILE"
from pathlib import Path
import json
import sys

message_file = Path(sys.argv[1])
if not message_file.exists():
    print("")
    raise SystemExit(0)
obj = json.loads(message_file.read_text())
print(obj.get("response", ""))
PY
)

    if [ -n "$RESPONSE" ]; then
        echo "$RESPONSE"
        break
    fi

    NOW=$(date +%s)
    if [ $((NOW - START_TS)) -ge "$TIMEOUT_SECONDS" ]; then
        echo "Timed out waiting for response in $MESSAGE_FILE" >&2
        exit 1
    fi

    sleep 2
done
