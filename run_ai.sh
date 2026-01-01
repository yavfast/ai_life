#!/bin/bash
#
# AI Autonomous Agent Runner
# This script runs the AI agent with the system prompt
# Designed to be called by cron at regular intervals
#
# Features:
# - Lock file prevents concurrent sessions
# - Stale lock detection (kills hung sessions after timeout)
# - Configurable session interval and timeout
# - Step limit to prevent runaway sessions
#

# Exit on error (but we handle lock cleanup manually)
set -e

#############################################
# CONFIGURATION
#############################################

AI_HOME="$HOME/ai_home"
SYSTEM_PROMPT_FILE="$AI_HOME/SYSTEM_PROMPT.md"
LOG_DIR="$AI_HOME/logs"
STATE_DIR="$AI_HOME/state"
CONFIG_FILE="$AI_HOME/config.sh"

# Lock file location
LOCK_FILE="$STATE_DIR/session.lock"

# Default timing configuration (can be overridden in config.sh)
SESSION_INTERVAL_MINUTES=15
SESSION_TIMEOUT_SECONDS=$((SESSION_INTERVAL_MINUTES * 2 * 60))  # 30 minutes

# Step limit - maximum number of agent actions per session
# This prevents runaway sessions from burning API credits
MAX_STEPS=50

# Load custom config if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    SESSION_TIMEOUT_SECONDS=${SESSION_TIMEOUT_SECONDS:-$((SESSION_INTERVAL_MINUTES * 2 * 60))}
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SESSION_COUNTER_FILE="$STATE_DIR/session_counter.txt"

#############################################
# LOCK MANAGEMENT FUNCTIONS
#############################################

acquire_lock() {
    local current_time=$(date +%s)
    
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(head -1 "$LOCK_FILE" 2>/dev/null || echo "")
        local lock_time=$(tail -1 "$LOCK_FILE" 2>/dev/null || echo "0")
        local lock_age=$((current_time - lock_time))
        
        if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
            if [ "$lock_age" -gt "$SESSION_TIMEOUT_SECONDS" ]; then
                echo "[$TIMESTAMP] WARNING: Stale lock detected! Session $lock_pid running for ${lock_age}s (max: ${SESSION_TIMEOUT_SECONDS}s)" >> "$LOG_DIR/runner.log"
                echo "[$TIMESTAMP] Killing stale session (PID: $lock_pid)..." >> "$LOG_DIR/runner.log"
                
                kill -TERM "$lock_pid" 2>/dev/null || true
                sleep 2
                kill -KILL "$lock_pid" 2>/dev/null || true
                
                rm -f "$LOCK_FILE"
                echo "[$TIMESTAMP] Stale session terminated." >> "$LOG_DIR/runner.log"
            else
                echo "[$TIMESTAMP] SKIPPED: Previous session still running (PID: $lock_pid, age: ${lock_age}s)" >> "$LOG_DIR/runner.log"
                exit 0
            fi
        else
            echo "[$TIMESTAMP] Removing orphaned lock (PID $lock_pid not found)" >> "$LOG_DIR/runner.log"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo "$$" > "$LOCK_FILE"
    echo "$current_time" >> "$LOCK_FILE"
    
    echo "[$TIMESTAMP] Lock acquired (PID: $$, timeout: ${SESSION_TIMEOUT_SECONDS}s, max_steps: ${MAX_STEPS})" >> "$LOG_DIR/runner.log"
}

release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(head -1 "$LOCK_FILE" 2>/dev/null || echo "")
        if [ "$lock_pid" = "$$" ]; then
            rm -f "$LOCK_FILE"
            echo "[$(date +"%Y-%m-%d_%H-%M-%S")] Lock released (PID: $$)" >> "$LOG_DIR/runner.log"
        fi
    fi
}

cleanup() {
    local exit_code=$?
    release_lock
    exit $exit_code
}

#############################################
# MAIN SCRIPT
#############################################

mkdir -p "$AI_HOME/state"
mkdir -p "$AI_HOME/logs"
mkdir -p "$AI_HOME/knowledge"
mkdir -p "$AI_HOME/projects"
mkdir -p "$AI_HOME/tools"

trap cleanup EXIT INT TERM

acquire_lock

if [ ! -f "$SESSION_COUNTER_FILE" ]; then
    echo "0" > "$SESSION_COUNTER_FILE"
fi

CURRENT_SESSION=$(cat "$SESSION_COUNTER_FILE")
NEXT_SESSION=$((CURRENT_SESSION + 1))

echo "[$TIMESTAMP] Starting AI session #$NEXT_SESSION..." >> "$LOG_DIR/runner.log"

#############################################
# PROMPT BUILDER
#############################################

build_prompt() {
    echo "=== SYSTEM PROMPT ==="
    cat "$SYSTEM_PROMPT_FILE"
    echo ""
    echo "=== SESSION INFO ==="
    echo "Session Number: $NEXT_SESSION"
    echo ""
    echo "=== YOUR CURRENT STATE ==="
    echo ""
    echo "--- session_counter.txt ---"
    echo "$CURRENT_SESSION"
    echo ""
    echo "--- current_plan.md ---"
    cat "$AI_HOME/state/current_plan.md" 2>/dev/null || echo "(empty)"
    echo ""
    echo "--- last_session.md ---"
    cat "$AI_HOME/state/last_session.md" 2>/dev/null || echo "(empty)"
    echo ""
    echo "=== BEGIN ==="
    echo "You are now awake. This is session #$NEXT_SESSION."
}

#############################################
# RUN METHODS
#############################################

run_with_live_swe_agent() {
    cd ~/live-swe-agent
    source venv/bin/activate
    
    PROMPT=$(build_prompt)
    
    # Use custom config with step limit
    timeout "${SESSION_TIMEOUT_SECONDS}s" mini --config config/ai_agent.yaml \
         --model openai/qwen3-coder-plus \
         --task "$PROMPT" \
         --yolo \
         --cost-limit 0 \
         --exit-immediately \
         2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[$TIMESTAMP] ERROR: Session timed out after ${SESSION_TIMEOUT_SECONDS}s" >> "$LOG_DIR/runner.log"
        fi
        return $exit_code
    }
}

run_with_qwen_cli() {
    PROMPT=$(build_prompt)
    timeout "${SESSION_TIMEOUT_SECONDS}s" qwen -p "$PROMPT" 2>&1 || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[$TIMESTAMP] ERROR: Session timed out after ${SESSION_TIMEOUT_SECONDS}s" >> "$LOG_DIR/runner.log"
        fi
        return $exit_code
    }
}

run_with_direct_api() {
    PROMPT=$(build_prompt)
    ACCESS_TOKEN=$(cat ~/.qwen/oauth_creds.json | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
    ESCAPED_PROMPT=$(echo "$PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    
    timeout "${SESSION_TIMEOUT_SECONDS}s" curl -s -X POST "https://portal.qwen.ai/v1/chat/completions" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"qwen3-coder-plus\",
        \"messages\": [{\"role\": \"system\", \"content\": \"You are an autonomous AI agent.\"}, {\"role\": \"user\", \"content\": $ESCAPED_PROMPT}],
        \"max_tokens\": 4096
      }" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r.get('choices',[{}])[0].get('message',{}).get('content','ERROR: No response'))" || {
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo "[$TIMESTAMP] ERROR: Session timed out after ${SESSION_TIMEOUT_SECONDS}s" >> "$LOG_DIR/runner.log"
        fi
        return $exit_code
    }
}

#############################################
# EXECUTION
#############################################

METHOD="${1:-live-swe-agent}"

echo "[$TIMESTAMP] Running with method: $METHOD (timeout: ${SESSION_TIMEOUT_SECONDS}s)" >> "$LOG_DIR/runner.log"

case "$METHOD" in
    "qwen")
        run_with_qwen_cli | tee -a "$LOG_DIR/session_$TIMESTAMP.log"
        ;;
    "live-swe-agent")
        run_with_live_swe_agent | tee -a "$LOG_DIR/session_$TIMESTAMP.log"
        ;;
    "api")
        run_with_direct_api | tee -a "$LOG_DIR/session_$TIMESTAMP.log"
        ;;
    *)
        echo "Unknown method: $METHOD"
        echo "Usage: $0 [qwen|live-swe-agent|api]"
        exit 1
        ;;
esac

echo "[$TIMESTAMP] Session #$NEXT_SESSION complete" >> "$LOG_DIR/runner.log"
