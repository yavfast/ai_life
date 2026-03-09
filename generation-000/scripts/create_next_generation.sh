#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_HOME="$(cd "$GENERATION_DIR/.." && pwd)"
SOURCE_NAME="$(basename "$GENERATION_DIR")"
TARGET_NAME="${1:-}"

if [ -z "$TARGET_NAME" ]; then
    echo "Usage: $0 generation-002" >&2
    exit 1
fi

TARGET_DIR="$RUNTIME_HOME/$TARGET_NAME"
SOURCE_AI_HOME="$GENERATION_DIR/ai_home"
TARGET_AI_HOME="$TARGET_DIR/ai_home"
DRAFT_DIR="$SOURCE_AI_HOME/state/next_generation"
DRAFT_FOUNDATION_DIR="$DRAFT_DIR/foundation"
DRAFT_SEED_DIR="$DRAFT_DIR/seed"

required_foundation_files=(
    "$DRAFT_FOUNDATION_DIR/01_physiology.md"
    "$DRAFT_FOUNDATION_DIR/02_subconscious.md"
    "$DRAFT_FOUNDATION_DIR/03_charter.md"
)

write_system_prompt_file() {
    local foundation_dir="$1"
    local output_file="$2"

    {
        echo "# Generation System Prompt"
        echo
        echo "This file is generated from ai_home/foundation/*.md."
        echo
        for part in \
            "$foundation_dir/01_physiology.md" \
            "$foundation_dir/02_subconscious.md" \
            "$foundation_dir/03_charter.md"; do
            cat "$part"
            echo
        done
    } > "$output_file"
}

if [ -e "$TARGET_DIR" ]; then
    echo "Target already exists: $TARGET_DIR" >&2
    exit 1
fi

for required_file in "${required_foundation_files[@]}"; do
    if [ ! -s "$required_file" ]; then
        echo "Missing required child foundation file: $required_file" >&2
        exit 1
    fi
done

mkdir -p "$TARGET_AI_HOME"
mkdir -p "$TARGET_AI_HOME/foundation" "$TARGET_AI_HOME/prompts" "$TARGET_AI_HOME/knowledge" "$TARGET_AI_HOME/logs" "$TARGET_AI_HOME/projects" "$TARGET_AI_HOME/state/inbox" "$TARGET_AI_HOME/state/next_generation/foundation" "$TARGET_AI_HOME/state/next_generation/seed" "$TARGET_AI_HOME/tools" "$TARGET_DIR/scripts"

echo "build" > "$TARGET_DIR/status.txt"

cp "$GENERATION_DIR/run_generation.sh" "$TARGET_DIR/run_generation.sh"
cp "$GENERATION_DIR/config.sh" "$TARGET_DIR/config.sh"
cp -R "$GENERATION_DIR/scripts/." "$TARGET_DIR/scripts/"
cp "$GENERATION_DIR/ai_home/prompts/identity_and_memory.md" "$TARGET_AI_HOME/prompts/identity_and_memory.md"
cp "$GENERATION_DIR/ai_home/prompts/lifecycle_and_succession.md" "$TARGET_AI_HOME/prompts/lifecycle_and_succession.md"
cp "$GENERATION_DIR/ai_home/prompts/zero_generation.md" "$TARGET_AI_HOME/prompts/zero_generation.md"
cp "$GENERATION_DIR/ai_home/state/inbox/README.md" "$TARGET_AI_HOME/state/inbox/README.md"
cp "$DRAFT_FOUNDATION_DIR/01_physiology.md" "$TARGET_AI_HOME/foundation/01_physiology.md"
cp "$DRAFT_FOUNDATION_DIR/02_subconscious.md" "$TARGET_AI_HOME/foundation/02_subconscious.md"
cp "$DRAFT_FOUNDATION_DIR/03_charter.md" "$TARGET_AI_HOME/foundation/03_charter.md"
write_system_prompt_file "$TARGET_AI_HOME/foundation" "$TARGET_AI_HOME/SYSTEM_PROMPT.md"

if [ -d "$DRAFT_SEED_DIR" ]; then
    python3 - <<'PY' "$DRAFT_SEED_DIR" "$TARGET_DIR"
from pathlib import Path
import shutil
import sys

seed_dir = Path(sys.argv[1])
target_dir = Path(sys.argv[2])

for source_path in seed_dir.rglob('*'):
    relative_path = source_path.relative_to(seed_dir)
    if relative_path == Path('README.md'):
        continue
    destination_path = target_dir / relative_path
    if source_path.is_dir():
        destination_path.mkdir(parents=True, exist_ok=True)
        continue
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_path, destination_path)
PY
fi

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
cat > "$TARGET_AI_HOME/state/last_session.md" <<EOF
# Last Session

$TARGET_NAME has just been created by $SOURCE_NAME.
EOF
cat > "$TARGET_AI_HOME/state/current_plan.md" <<EOF
# Current Plan

Bootstrap $TARGET_NAME and decide its first priorities.
EOF
cat > "$TARGET_AI_HOME/state/next_generation/README.md" <<EOF
# Next Generation Draft

Prepare the child foundation in \`foundation/\` and any optional overlay in \`seed/\` before creating the next generation.
EOF
cp "$TARGET_AI_HOME/foundation/01_physiology.md" "$TARGET_AI_HOME/state/next_generation/foundation/01_physiology.md"
cp "$TARGET_AI_HOME/foundation/02_subconscious.md" "$TARGET_AI_HOME/state/next_generation/foundation/02_subconscious.md"
cp "$TARGET_AI_HOME/foundation/03_charter.md" "$TARGET_AI_HOME/state/next_generation/foundation/03_charter.md"
cat > "$TARGET_AI_HOME/state/next_generation/seed/README.md" <<EOF
# Seed Overlay

Place optional child files here. They will be copied into the next child root during creation.
EOF
: > "$TARGET_AI_HOME/state/latest_response.md"
: > "$TARGET_AI_HOME/logs/runner.log"
echo "# History" > "$TARGET_AI_HOME/logs/history.md"
echo "# Consolidated History" > "$TARGET_AI_HOME/logs/consolidated_history.md"
echo "# Session Journal" > "$TARGET_AI_HOME/logs/session_journal.md"
rm -f "$TARGET_AI_HOME/state/session.lock"

# Activate only after the child is fully assembled
echo "active" > "$TARGET_DIR/status.txt"

echo "Created $TARGET_NAME at $TARGET_DIR"
