#!/bin/bash
# install_service.sh — Install AI Life as a systemd user service with a timer.
#
# Usage:
#   ./install_service.sh install  [--interval MINUTES] [--home PATH]
#   ./install_service.sh remove
#   ./install_service.sh status
#   ./install_service.sh enable
#   ./install_service.sh disable
#   ./install_service.sh start
#   ./install_service.sh logs

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$ROOT_DIR/run_ai.sh"
DEFAULT_INTERVAL=30
DEFAULT_RUNTIME_HOME="$HOME/.ai_life"
SERVICE_NAME="ai-life"
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_FILE="$SERVICE_DIR/${SERVICE_NAME}.service"
TIMER_FILE="$SERVICE_DIR/${SERVICE_NAME}.timer"

usage() {
    cat <<EOF
Usage: $0 COMMAND [OPTIONS]

Commands:
  install   Create and start a systemd user service + timer.
  remove    Stop, disable, and delete the service and timer.
  status    Show service and timer status.
  enable    Enable the timer to persist across reboots.
  disable   Disable the timer (stop automatic runs).
  start     Run the service once immediately.
  logs      Show recent journal logs for the service.

Options (for install):
  --interval MINUTES   Run interval in minutes (default: $DEFAULT_INTERVAL)
  --home PATH          Runtime home to pass to run_ai.sh (default: $DEFAULT_RUNTIME_HOME)

Examples:
  $0 install
  $0 install --interval 60 --home ~/.ai_life
  $0 status
  $0 logs
EOF
}

check_systemd_user() {
    if ! systemctl --user list-units >/dev/null 2>&1; then
        echo "Error: systemd user session is not available." >&2
        echo "       Make sure you are logged in as a regular user (not via su)." >&2
        exit 1
    fi
}

cmd_install() {
    local interval="$DEFAULT_INTERVAL"
    local runtime_home="$DEFAULT_RUNTIME_HOME"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --interval) interval="$2"; shift 2 ;;
            --home)     runtime_home="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
        echo "Error: --interval must be a positive integer." >&2
        exit 1
    fi

    check_systemd_user
    mkdir -p "$SERVICE_DIR"

    local log_file="$runtime_home/logs/service.log"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AI Life — autonomous generation dispatcher
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT --home $runtime_home
StandardOutput=append:$log_file
StandardError=append:$log_file
WorkingDirectory=$ROOT_DIR
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=AI Life dispatcher timer (every ${interval} min)

[Timer]
OnBootSec=2min
OnUnitActiveSec=${interval}min
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable "${SERVICE_NAME}.timer"
    systemctl --user start "${SERVICE_NAME}.timer"

    echo "✓ Service and timer installed:"
    echo "  Service  : $SERVICE_FILE"
    echo "  Timer    : $TIMER_FILE"
    echo "  Interval : every ${interval} min"
    echo "  Log      : $log_file"
    echo ""
    echo "Run '$0 status' to verify."
}

cmd_remove() {
    check_systemd_user

    systemctl --user stop  "${SERVICE_NAME}.timer"   2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user stop  "${SERVICE_NAME}.service" 2>/dev/null || true

    rm -f "$SERVICE_FILE" "$TIMER_FILE"
    systemctl --user daemon-reload

    echo "✓ Service and timer removed."
}

cmd_status() {
    check_systemd_user

    echo "=== Timer ==="
    systemctl --user status "${SERVICE_NAME}.timer" --no-pager 2>/dev/null \
        || echo "  Timer not installed."

    echo ""
    echo "=== Service (last run) ==="
    systemctl --user status "${SERVICE_NAME}.service" --no-pager 2>/dev/null \
        || echo "  Service not installed."
}

cmd_enable() {
    check_systemd_user
    systemctl --user enable "${SERVICE_NAME}.timer"
    systemctl --user start  "${SERVICE_NAME}.timer"
    echo "✓ Timer enabled."
}

cmd_disable() {
    check_systemd_user
    systemctl --user stop    "${SERVICE_NAME}.timer" 2>/dev/null || true
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null || true
    echo "✓ Timer disabled."
}

cmd_start() {
    check_systemd_user
    systemctl --user start "${SERVICE_NAME}.service"
    echo "✓ Service started. Use '$0 logs' to see output."
}

cmd_logs() {
    check_systemd_user
    journalctl --user -u "${SERVICE_NAME}.service" -n 80 --no-pager 2>/dev/null \
        || echo "No journal logs found."
}

main() {
    if [ "$#" -eq 0 ]; then
        usage
        exit 1
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        install)    cmd_install "$@" ;;
        remove)     cmd_remove ;;
        status)     cmd_status ;;
        enable)     cmd_enable ;;
        disable)    cmd_disable ;;
        start)      cmd_start ;;
        logs)       cmd_logs ;;
        -h|--help)  usage ;;
        *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
    esac
}

main "$@"
