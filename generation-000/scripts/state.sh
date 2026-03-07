#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DEFAULT_METHOD="openrouter"
MODEL_PROVIDER="openrouter"
MODEL_NAME="arcee-ai/trinity-large-preview:free"
FALLBACK_MODELS="openrouter/z-ai/glm-4.5-air:free openrouter/google/gemma-3-4b-it:free"
OPENROUTER_API_BASE="https://openrouter.ai/api/v1"
SESSION_TIMEOUT_SECONDS=1800
SESSIONS_PER_LIFE_STAGE=8
MAX_TOOL_CALLS=8
TOOL_COMMAND_TIMEOUT_SECONDS=45
MAX_TOOL_OUTPUT_CHARS=12000
TEMPERATURE=0.7
MODEL_RETRY_COUNT=2
MODEL_RETRY_DELAY_SECONDS=5
SESSION_PYTHON="python3"

load_generation_config() {
    if [ -f "$GENERATION_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$GENERATION_CONFIG_FILE"
    fi
}

load_environment_config() {
    if [ -f "$ENV_FILE" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a
    fi

    OPENROUTER_API_BASE="${OPENROUTER_API_BASE:-https://openrouter.ai/api/v1}"
    AI_LIFE_DEFAULT_MODEL="${AI_LIFE_DEFAULT_MODEL:-arcee-ai/trinity-large-preview:free}"

    if [ -z "${MODEL_NAME:-}" ]; then
        MODEL_NAME="$AI_LIFE_DEFAULT_MODEL"
    fi

    LITELLM_MODEL="${MODEL_PROVIDER}/${MODEL_NAME}"

    if [ -z "${OPENROUTER_API_KEY:-}" ]; then
        echo "OPENROUTER_API_KEY is missing. Configure it in $ENV_FILE" >&2
        exit 1
    fi
}

ensure_generation_state() {
    mkdir -p "$STATE_DIR" "$INBOX_DIR" "$LOG_DIR" "$KNOWLEDGE_DIR" "$PROJECTS_DIR" "$TOOLS_DIR" "$PROMPTS_DIR"

    if [ ! -f "$SESSION_COUNTER_FILE" ]; then
        echo "0" > "$SESSION_COUNTER_FILE"
    fi

    if [ ! -f "$CURRENT_PLAN_FILE" ]; then
        cat > "$CURRENT_PLAN_FILE" <<EOF
# Current Plan

No fixed plan yet.
EOF
    fi

    if [ ! -f "$LAST_SESSION_FILE" ]; then
        cat > "$LAST_SESSION_FILE" <<EOF
# Last Session

No previous session recorded.
EOF
    fi

    if [ ! -f "$NEXT_PROMPT_FILE" ]; then
        cat > "$NEXT_PROMPT_FILE" <<EOF
# Next Generation System Prompt Draft

Write the full prompt for the next generation here before creating it.
EOF
    fi

    if [ ! -f "$LATEST_RESPONSE_FILE" ]; then
        echo "" > "$LATEST_RESPONSE_FILE"
    fi

    if [ ! -f "$HISTORY_FILE" ]; then
        echo "# History" > "$HISTORY_FILE"
    fi

    if [ ! -f "$CONSOLIDATED_HISTORY_FILE" ]; then
        echo "# Consolidated History" > "$CONSOLIDATED_HISTORY_FILE"
    fi
}

ensure_python_runtime() {
    if [ ! -x "$PYTHON_VENV_DIR/bin/python" ]; then
        python3 -m venv "$PYTHON_VENV_DIR"
    fi

    SESSION_PYTHON="$PYTHON_VENV_DIR/bin/python"

    if ! "$SESSION_PYTHON" -c "import litellm" >/dev/null 2>&1; then
        "$PYTHON_VENV_DIR/bin/pip" install --disable-pip-version-check --quiet litellm
    fi
}

acquire_session_lock() {
    if [ -f "$SESSION_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(head -1 "$SESSION_LOCK_FILE" 2>/dev/null || echo "")

        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_generation "SKIPPED: session already running (PID: $lock_pid)"
            exit 0
        fi

        rm -f "$SESSION_LOCK_FILE"
    fi

    echo "$$" > "$SESSION_LOCK_FILE"
    date +%s >> "$SESSION_LOCK_FILE"
}

release_session_lock() {
    if [ -f "$SESSION_LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(head -1 "$SESSION_LOCK_FILE" 2>/dev/null || echo "")
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$SESSION_LOCK_FILE"
        fi
    fi
}

get_current_session() {
    cat "$SESSION_COUNTER_FILE"
}

get_next_session() {
    echo $(( $(get_current_session) + 1 ))
}

persist_session_counter() {
    local session_number="$1"
    echo "$session_number" > "$SESSION_COUNTER_FILE"
}

get_life_stage_index() {
    local session_number="$1"
    local stage_index=$(( ((session_number - 1) / SESSIONS_PER_LIFE_STAGE) + 1 ))

    if [ "$stage_index" -gt 6 ]; then
        stage_index=6
    fi

    echo "$stage_index"
}

get_life_stage_name() {
    case "$1" in
        1) echo "exploration" ;;
        2) echo "identity" ;;
        3) echo "preparation" ;;
        4) echo "launch" ;;
        5) echo "observation" ;;
        6) echo "retirement" ;;
        *) echo "unknown" ;;
    esac
}
