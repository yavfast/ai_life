#!/bin/bash
# manage_cron.sh — Create, update, or remove the cron job for AI Life dispatcher.
#
# Usage:
#   ./manage_cron.sh install [--interval MINUTES] [--home PATH]
#   ./manage_cron.sh remove
#   ./manage_cron.sh show

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$ROOT_DIR/run_ai.sh"
DEFAULT_INTERVAL=30
DEFAULT_RUNTIME_HOME="$HOME/.ai_life"
CRON_MARKER="# ai_life"

usage() {
    cat <<EOF
Usage: $0 COMMAND [OPTIONS]

Commands:
  install   Add or update the cron job for AI Life dispatcher.
  remove    Remove AI Life cron job.
  show      Show the current AI Life cron entry.

Options (for install):
  --interval MINUTES   Run interval in minutes (default: $DEFAULT_INTERVAL)
  --home PATH          Runtime home to pass to run_ai.sh (default: $DEFAULT_RUNTIME_HOME)

Examples:
  $0 install
  $0 install --interval 60 --home ~/.ai_life
  $0 remove
  $0 show
EOF
}

get_current_crontab() {
    crontab -l 2>/dev/null || true
}

remove_ai_life_entries() {
    local new_content
    new_content=$(get_current_crontab | grep -v "run_ai\.sh" | grep -v "$CRON_MARKER" || true)
    echo "$new_content" | crontab -
}

cmd_install() {
    local interval="$DEFAULT_INTERVAL"
    local runtime_home="$DEFAULT_RUNTIME_HOME"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --interval) interval="$2"; shift 2 ;;
            --home)     runtime_home="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        esac
    done

    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
        echo "Error: --interval must be a positive integer." >&2
        exit 1
    fi

    local cron_schedule
    if [ "$interval" -lt 60 ]; then
        cron_schedule="*/$interval * * * *"
    elif [ "$interval" -eq 60 ]; then
        cron_schedule="0 * * * *"
    else
        local hours=$(( interval / 60 ))
        cron_schedule="0 */$hours * * *"
    fi

    local log_file="$runtime_home/logs/cron.log"
    local cron_line="$cron_schedule  bash \"$SCRIPT\" --home \"$runtime_home\" >> \"$log_file\" 2>&1  $CRON_MARKER"

    remove_ai_life_entries

    {
        get_current_crontab
        echo "$cron_line"
    } | crontab -

    echo "✓ Cron job installed (every ${interval} min):"
    echo "  Entry : $cron_line"
    echo "  Log   : $log_file"
    echo ""
    echo "Verify with: $0 show"
}

cmd_remove() {
    remove_ai_life_entries
    echo "✓ AI Life cron job removed."
}

cmd_show() {
    local entry
    entry=$(get_current_crontab | grep "run_ai\.sh" || true)
    if [ -z "$entry" ]; then
        echo "No AI Life cron job found."
    else
        echo "Current AI Life cron entry:"
        echo "$entry"
    fi
}

main() {
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        install)        cmd_install "$@" ;;
        remove)         cmd_remove ;;
        show)           cmd_show ;;
        -h|--help)      usage ;;
        *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
    esac
}

main "$@"
