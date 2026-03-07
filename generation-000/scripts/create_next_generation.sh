#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_HOME="$(cd "$GENERATION_DIR/.." && pwd)"
SOURCE_NAME="$(basename "$GENERATION_DIR")"
TARGET_NAME="${1:-}"
ACTIVATE_FLAG="${2:-}"

if [ -z "$TARGET_NAME" ]; then
    echo "Usage: $0 generation-002 [--activate]" >&2
    exit 1
fi

TARGET_DIR="$RUNTIME_HOME/$TARGET_NAME"
SOURCE_AI_HOME="$GENERATION_DIR/ai_home"
TARGET_AI_HOME="$TARGET_DIR/ai_home"
NEXT_PROMPT_FILE="$SOURCE_AI_HOME/state/next_generation_system_prompt.md"
ACTIVE_GENERATIONS_FILE="$RUNTIME_HOME/state/active_generations.txt"

if [ -e "$TARGET_DIR" ]; then
    echo "Target already exists: $TARGET_DIR" >&2
    exit 1
fi

if [ ! -s "$NEXT_PROMPT_FILE" ]; then
    echo "Missing next-generation prompt draft: $NEXT_PROMPT_FILE" >&2
    exit 1
fi

cp -R "$GENERATION_DIR" "$TARGET_DIR"
cp "$NEXT_PROMPT_FILE" "$TARGET_AI_HOME/SYSTEM_PROMPT.md"
rm -f "$TARGET_AI_HOME/state/session.lock"

python3 - <<'PY' "$TARGET_DIR" "$TARGET_NAME"
from pathlib import Path
import sys

target_dir = Path(sys.argv[1])
target_name = sys.argv[2]
for path in target_dir.rglob('*'):
    if path.is_file():
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        updated = text.replace('generation-000', target_name)
        if updated != text:
            path.write_text(updated)
PY

echo "0" > "$TARGET_AI_HOME/state/session_counter.txt"
mkdir -p "$TARGET_AI_HOME/state/inbox"
cat > "$TARGET_AI_HOME/state/last_session.md" <<EOF
# Last Session

$TARGET_NAME has just been created by $SOURCE_NAME.
EOF
cat > "$TARGET_AI_HOME/state/current_plan.md" <<EOF
# Current Plan

Bootstrap $TARGET_NAME and decide its first priorities.
EOF
cat > "$TARGET_AI_HOME/state/next_generation_system_prompt.md" <<EOF
# Next Generation System Prompt Draft

Write the full prompt for the next generation here before creating it.
EOF
: > "$TARGET_AI_HOME/state/latest_response.md"
: > "$TARGET_AI_HOME/logs/runner.log"
echo "# History" > "$TARGET_AI_HOME/logs/history.md"
echo "# Consolidated History" > "$TARGET_AI_HOME/logs/consolidated_history.md"
rm -f "$TARGET_AI_HOME/state/inbox"/*.json 2>/dev/null || true

if [ "$ACTIVATE_FLAG" = "--activate" ]; then
    touch "$ACTIVE_GENERATIONS_FILE"
    if ! grep -qx "$TARGET_NAME" "$ACTIVE_GENERATIONS_FILE"; then
        echo "$TARGET_NAME" >> "$ACTIVE_GENERATIONS_FILE"
    fi
fi

echo "Created $TARGET_NAME at $TARGET_DIR"
