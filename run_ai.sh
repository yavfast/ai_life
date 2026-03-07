#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_GENERATION_DIR="$ROOT_DIR/generation-000"
DEFAULT_RUNTIME_HOME="$HOME/.ai_life"
DEFAULT_METHOD="openrouter"
RUNTIME_HOME="$DEFAULT_RUNTIME_HOME"
METHOD="$DEFAULT_METHOD"
ONLY_GENERATION=""
LOCK_FILE=""
DISPATCHER_LOG_FILE=""
ACTIVE_GENERATIONS_FILE=""

usage() {
    cat <<EOF
Usage: $0 [--home PATH] [--only GENERATION] [method]

Options:
  --home PATH         Runtime home for live generations. Default: $DEFAULT_RUNTIME_HOME
  --only GENERATION   Run only one generation immediately.
  -h, --help          Show this help.

Methods:
  openrouter          Default LiteLLM provider path.
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --home)
                RUNTIME_HOME="$2"
                shift 2
                ;;
            --only)
                ONLY_GENERATION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                METHOD="$1"
                shift
                ;;
        esac
    done
}

timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

log_dispatcher() {
    mkdir -p "$(dirname "$DISPATCHER_LOG_FILE")"
    echo "[$(timestamp)] $*" >> "$DISPATCHER_LOG_FILE"
}

load_env_file() {
    if [ -f "$ROOT_DIR/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        source "$ROOT_DIR/.env"
        set +a
    fi
}

rewrite_generation_name() {
    local target_dir="$1"
    local target_name="$2"

    python3 - <<'PY' "$target_dir" "$target_name"
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
}

bootstrap_generation() {
    local target_name="$1"
    local target_dir="$RUNTIME_HOME/$target_name"

    if [ -d "$target_dir" ]; then
        return 0
    fi

    mkdir -p "$RUNTIME_HOME"
    cp -R "$TEMPLATE_GENERATION_DIR" "$target_dir"
    rewrite_generation_name "$target_dir" "$target_name"
    rm -f "$target_dir/ai_home/state/session.lock"
    echo "0" > "$target_dir/ai_home/state/session_counter.txt"

    cat > "$target_dir/ai_home/state/last_session.md" <<EOF
# Last Session

$target_name has just been bootstrapped from the repository template.
EOF

    cat > "$target_dir/ai_home/state/current_plan.md" <<EOF
# Current Plan

Bootstrap $target_name and decide its first priorities.
EOF

    cat > "$target_dir/ai_home/state/next_generation_system_prompt.md" <<EOF
# Next Generation System Prompt Draft

Write the full prompt for the next generation here before creating it.
EOF

    mkdir -p "$target_dir/ai_home/state/inbox"
    : > "$target_dir/ai_home/state/latest_response.md"
    : > "$target_dir/ai_home/logs/runner.log"
    echo "# History" > "$target_dir/ai_home/logs/history.md"
    echo "# Consolidated History" > "$target_dir/ai_home/logs/consolidated_history.md"
}

ensure_runtime_home() {
    mkdir -p "$RUNTIME_HOME/state" "$RUNTIME_HOME/logs"
    LOCK_FILE="$RUNTIME_HOME/state/dispatcher.lock"
    DISPATCHER_LOG_FILE="$RUNTIME_HOME/logs/dispatcher.log"
    ACTIVE_GENERATIONS_FILE="$RUNTIME_HOME/state/active_generations.txt"

    bootstrap_generation "generation-001"

    if [ ! -f "$ACTIVE_GENERATIONS_FILE" ]; then
        echo "generation-001" > "$ACTIVE_GENERATIONS_FILE"
    fi
}

acquire_lock() {
    local current_time
    current_time=$(date +%s)

    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(head -1 "$LOCK_FILE" 2>/dev/null || echo "")

        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            log_dispatcher "SKIPPED: dispatcher already running (PID: $lock_pid)"
            exit 0
        fi

        rm -f "$LOCK_FILE"
    fi

    echo "$$" > "$LOCK_FILE"
    echo "$current_time" >> "$LOCK_FILE"
}

release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(head -1 "$LOCK_FILE" 2>/dev/null || echo "")
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$LOCK_FILE"
        fi
    fi
}

cleanup() {
    local exit_code=$?
    release_lock
    exit $exit_code
}

read_active_generations() {
    grep -v '^[[:space:]]*#' "$ACTIVE_GENERATIONS_FILE" | sed '/^[[:space:]]*$/d'
}

run_generation() {
    local generation_name="$1"
    local generation_dir="$RUNTIME_HOME/$generation_name"
    local generation_runner="$generation_dir/run_generation.sh"
    local generation_log="$RUNTIME_HOME/logs/${generation_name}.log"

    if [ ! -d "$generation_dir" ]; then
        log_dispatcher "SKIPPED: missing generation directory $generation_name"
        return 0
    fi

    if [ ! -x "$generation_runner" ]; then
        log_dispatcher "SKIPPED: missing executable runner $generation_runner"
        return 0
    fi

    log_dispatcher "Dispatching $generation_name with method $METHOD"

    if AI_LIFE_RUNTIME_HOME="$RUNTIME_HOME" AI_LIFE_REPO_ROOT="$ROOT_DIR" "$generation_runner" "$METHOD" >> "$generation_log" 2>&1; then
        log_dispatcher "Completed $generation_name successfully"
    else
        local exit_code=$?
        log_dispatcher "FAILED: $generation_name exited with code $exit_code"
        return $exit_code
    fi
}

main() {
    parse_args "$@"
    load_env_file
    ensure_runtime_home
    trap cleanup EXIT INT TERM
    acquire_lock

    log_dispatcher "Dispatcher start (method: $METHOD, runtime_home: $RUNTIME_HOME)"

    if [ -n "$ONLY_GENERATION" ]; then
        run_generation "$ONLY_GENERATION"
    else
        while IFS= read -r generation_name; do
            run_generation "$generation_name"
        done < <(read_active_generations)
    fi

    log_dispatcher "Dispatcher complete"
}

main "$@"
