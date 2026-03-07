#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_GENERATION_DIR="$ROOT_DIR/generation-000"
DEFAULT_RUNTIME_HOME="$HOME/.ai_life"
DEFAULT_METHOD="openrouter"
RUNTIME_HOME="$DEFAULT_RUNTIME_HOME"
METHOD="$DEFAULT_METHOD"
ONLY_GENERATION=""
STATUS_MODE=false
LOCK_FILE=""
DISPATCHER_LOG_FILE=""
ACTIVE_GENERATIONS_FILE=""

# Colors (only when stdout is an interactive terminal)
if [ -t 1 ]; then
    C_BOLD='\033[1m'; C_DIM='\033[2m'; C_RESET='\033[0m'
    C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
    C_YELLOW='\033[1;33m'; C_CYAN='\033[0;36m'
else
    C_BOLD=''; C_DIM=''; C_RESET=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''
fi

cprint() { printf "${1}%s${C_RESET}\n" "$2"; }

usage() {
    cat <<EOF
Usage: $0 [--home PATH] [--only GENERATION] [--status] [method]

Options:
  --home PATH         Runtime home for live generations. Default: $DEFAULT_RUNTIME_HOME
  --only GENERATION   Run only one generation immediately.
  --status            Show current status and exit (no sessions started).
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
            --status)
                STATUS_MODE=true
                shift
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

show_status() {
    printf "\n${C_BOLD}══════════════════════════════════════════════════${C_RESET}\n"
    printf "${C_BOLD}  AI Life — Status${C_RESET}\n"
    printf "${C_DIM}  Runtime home : %s${C_RESET}\n" "$RUNTIME_HOME"
    printf "${C_BOLD}══════════════════════════════════════════════════${C_RESET}\n\n"

    if [ ! -d "$RUNTIME_HOME" ]; then
        cprint "$C_YELLOW" "  Runtime home does not exist. Run without --status to bootstrap."
        return 0
    fi

    local lock_file="$RUNTIME_HOME/state/dispatcher.lock"
    if [ -f "$lock_file" ]; then
        local lock_pid
        lock_pid=$(head -1 "$lock_file" 2>/dev/null || echo "")
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            printf "  Dispatcher : ${C_GREEN}RUNNING${C_RESET} (PID %s)\n" "$lock_pid"
        else
            printf "  Dispatcher : ${C_DIM}idle (stale lock)${C_RESET}\n"
        fi
    else
        printf "  Dispatcher : ${C_DIM}idle${C_RESET}\n"
    fi
    echo ""

    local active_file="$RUNTIME_HOME/state/active_generations.txt"
    if [ ! -f "$active_file" ]; then
        cprint "$C_YELLOW" "  No active_generations.txt found."
        return 0
    fi

    local stage_names=("bootstrap" "explorer" "builder" "optimizer" "mentor" "legacy" "complete")

    while IFS= read -r gen_name; do
        [ -z "$gen_name" ] && continue
        local gen_dir="$RUNTIME_HOME/$gen_name"
        printf "  ${C_BOLD}${C_CYAN}▸ %s${C_RESET}\n" "$gen_name"

        if [ ! -d "$gen_dir" ]; then
            printf "    ${C_RED}Directory missing${C_RESET}\n\n"
            continue
        fi

        local model_name=""
        if [ -f "$gen_dir/config.sh" ]; then
            model_name=$(grep '^MODEL_NAME=' "$gen_dir/config.sh" | head -1 | cut -d= -f2- | tr -d '"')
        fi
        printf "    Model   : %s\n" "${model_name:-<unknown>}"

        local session_count=0
        if [ -f "$gen_dir/ai_home/state/session_counter.txt" ]; then
            session_count=$(cat "$gen_dir/ai_home/state/session_counter.txt")
        fi
        printf "    Sessions: %s\n" "$session_count"

        local sessions_per_stage=8
        if [ -f "$gen_dir/config.sh" ]; then
            local sps
            sps=$(grep '^SESSIONS_PER_LIFE_STAGE=' "$gen_dir/config.sh" | head -1 | cut -d= -f2- | tr -d '"')
            [ -n "$sps" ] && sessions_per_stage=$sps
        fi
        local stage_idx=$(( session_count / sessions_per_stage ))
        [ "$stage_idx" -gt 6 ] && stage_idx=6
        printf "    Stage   : %d/6 (%s)\n" "$stage_idx" "${stage_names[$stage_idx]}"

        local session_lock="$gen_dir/ai_home/state/session.lock"
        if [ -f "$session_lock" ]; then
            local sess_pid
            sess_pid=$(head -1 "$session_lock" 2>/dev/null || echo "")
            if [ -n "$sess_pid" ] && kill -0 "$sess_pid" 2>/dev/null; then
                printf "    Session : ${C_GREEN}RUNNING${C_RESET} (PID %s)\n" "$sess_pid"
            else
                printf "    Session : ${C_DIM}idle${C_RESET}\n"
            fi
        else
            printf "    Session : ${C_DIM}idle${C_RESET}\n"
        fi

        local inbox_dir="$gen_dir/ai_home/state/inbox"
        if [ -d "$inbox_dir" ]; then
            local pending_count=0
            pending_count=$(grep -rl '"status": "pending"' "$inbox_dir" 2>/dev/null | wc -l) || pending_count=0
            if [ "${pending_count:-0}" -gt 0 ]; then
                printf "    Inbox   : ${C_YELLOW}%s pending message(s)${C_RESET}\n" "$pending_count"
            else
                printf "    Inbox   : no pending messages\n"
            fi
        fi

        local last_session_file="$gen_dir/ai_home/state/last_session.md"
        if [ -f "$last_session_file" ]; then
            local mod_time
            mod_time=$(date -r "$last_session_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            printf "    Last run: %s\n" "$mod_time"
        fi

        echo ""
    done < <(grep -v '^[[:space:]]*#' "$active_file" | sed '/^[[:space:]]*$/d')
}

run_generation() {
    local generation_name="$1"
    local generation_dir="$RUNTIME_HOME/$generation_name"
    local generation_runner="$generation_dir/run_generation.sh"
    local generation_log="$RUNTIME_HOME/logs/${generation_name}.log"

    if [ ! -d "$generation_dir" ]; then
        log_dispatcher "SKIPPED: missing generation directory $generation_name"
        cprint "$C_YELLOW" "  ⚠  Skipped $generation_name: directory missing"
        return 0
    fi

    if [ ! -x "$generation_runner" ]; then
        log_dispatcher "SKIPPED: missing executable runner $generation_runner"
        cprint "$C_YELLOW" "  ⚠  Skipped $generation_name: runner not executable"
        return 0
    fi

    local model_display=""
    if [ -f "$generation_dir/config.sh" ]; then
        model_display=$(grep '^MODEL_NAME=' "$generation_dir/config.sh" | head -1 | cut -d= -f2- | tr -d '"')
    fi

    local session_num="?"
    if [ -f "$generation_dir/ai_home/state/session_counter.txt" ]; then
        session_num=$(( $(cat "$generation_dir/ai_home/state/session_counter.txt") + 1 ))
    fi

    printf "\n${C_BOLD}${C_CYAN}▶ %s${C_RESET}  session #%s\n" "$generation_name" "$session_num"
    printf "   model : %s\n" "${model_display:-<unknown>}"
    printf "   log   : %s\n" "$generation_log"
    printf "   start : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

    log_dispatcher "Dispatching $generation_name (model: ${model_display:-?}, session: #${session_num}, method: $METHOD)"

    local start_ts exit_code=0
    start_ts=$(date +%s)

    set +e
    AI_LIFE_RUNTIME_HOME="$RUNTIME_HOME" AI_LIFE_REPO_ROOT="$ROOT_DIR" "$generation_runner" "$METHOD" 2>&1 | tee -a "$generation_log"
    exit_code=${PIPESTATUS[0]}
    set -e

    local duration_s=$(( $(date +%s) - start_ts ))

    if [ "$exit_code" -eq 0 ]; then
        log_dispatcher "Completed $generation_name successfully (${duration_s}s)"
        printf "\n${C_GREEN}✓ %s completed in %ds${C_RESET}\n" "$generation_name" "$duration_s"
    else
        log_dispatcher "FAILED: $generation_name exited with code $exit_code (${duration_s}s)"
        printf "\n${C_RED}✗ %s failed (exit %d, %ds)${C_RESET}\n" "$generation_name" "$exit_code" "$duration_s"
        return $exit_code
    fi
}

main() {
    parse_args "$@"
    load_env_file
    ensure_runtime_home

    if $STATUS_MODE; then
        show_status
        return 0
    fi

    trap cleanup EXIT INT TERM
    acquire_lock

    printf "\n${C_BOLD}══════════════════════════════════════════════════${C_RESET}\n"
    printf "${C_BOLD}  AI Life Dispatcher${C_RESET}   %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf "  Runtime home : ${C_DIM}%s${C_RESET}\n" "$RUNTIME_HOME"
    printf "  Method       : %s\n" "$METHOD"
    printf "${C_BOLD}══════════════════════════════════════════════════${C_RESET}\n"

    log_dispatcher "Dispatcher start (method: $METHOD, runtime_home: $RUNTIME_HOME)"

    if [ -n "$ONLY_GENERATION" ]; then
        run_generation "$ONLY_GENERATION"
    else
        while IFS= read -r generation_name; do
            run_generation "$generation_name"
        done < <(read_active_generations)
    fi

    log_dispatcher "Dispatcher complete"
    printf "\n${C_DIM}Dispatcher finished at $(date '+%H:%M:%S')${C_RESET}\n\n"
}

main "$@"
