#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/agent_session.sh"

cleanup() {
    local exit_code=$?
    release_session_lock
    exit $exit_code
}

main() {
    local method current_session next_session stage_index stage_name session_log
    method="${1:-$DEFAULT_METHOD}"

    load_generation_config
    load_environment_config
    ensure_generation_state

    if ! is_generation_active; then
        echo "  Generation : $GENERATION_NAME"
        echo "  Status     : $(get_generation_status)"
        echo "  Skipped    : only active generations may run"
        exit 0
    fi

    ensure_python_runtime

    trap cleanup EXIT INT TERM
    acquire_session_lock

    current_session=$(get_current_session)
    next_session=$(get_next_session)
    stage_index=$(get_life_stage_index "$next_session")
    stage_name=$(get_life_stage_name "$stage_index")
    session_log="$LOG_DIR/session_$(timestamp).log"

    echo "  Generation : $GENERATION_NAME"
    echo "  Model      : $LITELLM_MODEL"
    echo "  Session    : #$next_session"
    echo "  Stage      : $stage_index/6 ($stage_name)"
    echo "  Session log: $session_log"

    log_generation "Starting session $next_session for $GENERATION_NAME (stage $stage_index/6: $stage_name, method: $method)"

    local start_ts exit_code=0
    start_ts=$(date +%s)

    if run_agent_session "$method" "$next_session" "$stage_index" "$stage_name" >> "$session_log" 2>&1; then
        local duration_s=$(( $(date +%s) - start_ts ))
        persist_session_counter "$next_session"
        log_generation "Completed session $next_session for $GENERATION_NAME (${duration_s}s)"
        echo "  Duration   : ${duration_s}s"
        echo "  Finished   : $(date '+%Y-%m-%d %H:%M:%S')"
    else
        exit_code=$?
        local duration_s=$(( $(date +%s) - start_ts ))
        log_generation "FAILED session $next_session for $GENERATION_NAME with exit code $exit_code (${duration_s}s)"
        echo "  Duration   : ${duration_s}s  [FAILED, exit $exit_code]" >&2
        return $exit_code
    fi
}

main "$@"
