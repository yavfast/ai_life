#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.sh"

run_agent_session() {
    local method="$1"
    local next_session="$2"
    local stage_index="$3"
    local stage_name="$4"

    if [ "$method" != "openrouter" ]; then
        echo "Unsupported method: $method" >&2
        return 1
    fi

    AI_LIFE_METHOD="$method" \
    AI_LIFE_SESSION_NUMBER="$next_session" \
    AI_LIFE_STAGE_INDEX="$stage_index" \
    AI_LIFE_STAGE_NAME="$stage_name" \
    AI_LIFE_GENERATION_DIR="$GENERATION_DIR" \
    AI_LIFE_RUNTIME_HOME="$RUNTIME_HOME" \
    AI_LIFE_MODEL="$LITELLM_MODEL" \
    AI_LIFE_FALLBACK_MODELS="$FALLBACK_MODELS" \
    AI_LIFE_OPENROUTER_API_BASE="$OPENROUTER_API_BASE" \
    AI_LIFE_MAX_TOOL_CALLS="$MAX_TOOL_CALLS" \
    AI_LIFE_TOOL_TIMEOUT="$TOOL_COMMAND_TIMEOUT_SECONDS" \
    AI_LIFE_MAX_TOOL_OUTPUT_CHARS="$MAX_TOOL_OUTPUT_CHARS" \
    AI_LIFE_TEMPERATURE="$TEMPERATURE" \
    AI_LIFE_MODEL_RETRY_COUNT="$MODEL_RETRY_COUNT" \
    AI_LIFE_MODEL_RETRY_DELAY_SECONDS="$MODEL_RETRY_DELAY_SECONDS" \
    timeout "${SESSION_TIMEOUT_SECONDS}s" "$SESSION_PYTHON" "$SESSION_RUNNER_PY"
}
