#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.sh"

render_pending_messages() {
    python3 - <<'PY' "$INBOX_DIR"
from pathlib import Path
import json
import sys

inbox = Path(sys.argv[1])
messages = []
for path in sorted(inbox.glob('*.json')):
    try:
        data = json.loads(path.read_text())
    except Exception:
        continue
    if data.get('status') == 'pending':
        messages.append(f"- {path.name}: {data.get('content', '').strip()}")

if messages:
    print("\n".join(messages))
else:
    print("(none)")
PY
}

build_prompt() {
    local current_session next_session stage_index stage_name pending_messages
    current_session=$(get_current_session)
    next_session=$(get_next_session)
    stage_index=$(get_life_stage_index "$next_session")
    stage_name=$(get_life_stage_name "$stage_index")
    pending_messages=$(render_pending_messages)

    cat <<EOF
=== SYSTEM PROMPT ===
$(cat "$AI_HOME/SYSTEM_PROMPT.md")

=== IMPORTANT GUIDELINES ===
--- identity_and_memory.md ---
$(cat "$PROMPTS_DIR/identity_and_memory.md" 2>/dev/null || echo "N/A")

--- lifecycle_and_succession.md ---
$(cat "$PROMPTS_DIR/lifecycle_and_succession.md" 2>/dev/null || echo "N/A")

--- zero_generation.md ---
$(cat "$PROMPTS_DIR/zero_generation.md" 2>/dev/null || echo "N/A")

=== SESSION INFO ===
Generation Name: $GENERATION_NAME
Session Number: $next_session
Previous Session Number: $current_session
Life Stage: $stage_index/6 ($stage_name)
Generation Directory: $GENERATION_DIR
Runtime Home: $RUNTIME_HOME
Current Plan File: $CURRENT_PLAN_FILE
Last Session File: $LAST_SESSION_FILE
Next Generation Prompt Draft: $NEXT_PROMPT_FILE
Inbox Directory: $INBOX_DIR
Pending User Messages:
$pending_messages

=== LOCAL STATE ===
--- current_plan.md ---
$(cat "$CURRENT_PLAN_FILE")

--- last_session.md ---
$(cat "$LAST_SESSION_FILE")
EOF
}
