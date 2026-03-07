#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths.sh"

timestamp() {
    date +"%Y-%m-%d_%H-%M-%S"
}

utc_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_generation() {
    mkdir -p "$LOG_DIR"
    echo "[$(timestamp)] $*" >> "$GENERATION_RUNNER_LOG"
}
