#!/bin/bash
#
# Deploy AI Agent to server
# This script deploys all configuration files to the remote server
#
# Usage:
#   ./deploy.sh              # Deploy everything (creates dirs, deploys files)
#   ./deploy.sh --reset      # Deploy + reset agent state (fresh session 1)
#   ./deploy.sh --config     # Deploy only config files (keep agent's state)
#   ./deploy.sh --sync-token # Just sync OAuth token to agent config
#

set -e

SERVER="debian"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${GREEN}==>${NC} $1"; }

# Parse arguments
RESET_STATE=false
CONFIG_ONLY=false
SYNC_TOKEN_ONLY=false

for arg in "$@"; do
    case $arg in
        --reset)
            RESET_STATE=true
            ;;
        --config)
            CONFIG_ONLY=true
            ;;
        --sync-token)
            SYNC_TOKEN_ONLY=true
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --reset       Reset agent state (fresh start from session 1)"
            echo "  --config      Deploy only config files (keep agent's work)"
            echo "  --sync-token  Just sync OAuth token to agent config"
            echo "  --help        Show this help"
            exit 0
            ;;
    esac
done

echo "========================================"
echo "   AI Agent Deployment Script"
echo "========================================"

# Check SSH connectivity first
log_step "Checking server connectivity..."
if ! ssh -o ConnectTimeout=5 "$SERVER" "echo 'OK'" > /dev/null 2>&1; then
    log_error "Cannot connect to server '$SERVER'"
    exit 1
fi
log_info "Connected to $SERVER"

# Sync token only mode
if [ "$SYNC_TOKEN_ONLY" = true ]; then
    log_step "Syncing OAuth token..."
    ssh "$SERVER" "~/sync-qwen-token.sh --force" && log_info "Token synced" || log_error "Token sync failed"
    exit $?
fi

# Step 1: Create directory structure FIRST (before any file copies)
log_step "Creating directory structure on server..."
ssh "$SERVER" "mkdir -p ~/ai_home/{state,logs,knowledge,projects,tools}"
log_info "Directories created"

# Step 2: Deploy all files
log_step "Deploying files..."

# System prompt
scp -q "$SCRIPT_DIR/SYSTEM_PROMPT.md" "$SERVER:~/ai_home/SYSTEM_PROMPT.md"
log_info "SYSTEM_PROMPT.md"

# Run script
scp -q "$SCRIPT_DIR/run_ai.sh" "$SERVER:~/run_ai.sh"
ssh "$SERVER" "chmod +x ~/run_ai.sh"
log_info "run_ai.sh"

# Agent config (for mini-swe-agent)
scp -q "$SCRIPT_DIR/config/ai_agent.yaml" "$SERVER:~/live-swe-agent/config/ai_agent.yaml"
log_info "ai_agent.yaml"

# Config.sh
scp -q "$SCRIPT_DIR/ai_home/config.sh" "$SERVER:~/ai_home/config.sh"
log_info "config.sh"

# Sync token script
scp -q "$SCRIPT_DIR/sync-qwen-token.sh" "$SERVER:~/sync-qwen-token.sh"
ssh "$SERVER" "chmod +x ~/sync-qwen-token.sh"
log_info "sync-qwen-token.sh"

# Config-only mode stops here
if [ "$CONFIG_ONLY" = true ]; then
    log_step "Config-only deployment complete!"
    echo ""
    echo "Note: Agent state was preserved. Use --reset to start fresh."
    exit 0
fi

# Step 3: Initialize or reset state
if [ "$RESET_STATE" = true ]; then
    log_step "Resetting agent state..."
    
    # Stop any running sessions
    ssh "$SERVER" "pkill -f 'mini --config' 2>/dev/null || true; rm -f ~/ai_home/state/session.lock"
    log_info "Stopped running sessions"
    
    # Reset all state in one SSH call
    ssh "$SERVER" "
        echo '0' > ~/ai_home/state/session_counter.txt
        echo '(no previous session)' > ~/ai_home/state/last_session.md
        echo '(no plan yet)' > ~/ai_home/state/current_plan.md
        echo '# AI History Log' > ~/ai_home/logs/history.md
        echo '# Consolidated History' > ~/ai_home/logs/consolidated_history.md
    "
    log_info "State reset to session 0"
else
    # Just ensure state files exist (don't overwrite)
    log_step "Ensuring state files exist..."
    ssh "$SERVER" "
        [ -f ~/ai_home/state/session_counter.txt ] || echo '0' > ~/ai_home/state/session_counter.txt
        [ -f ~/ai_home/state/last_session.md ] || echo '(no previous session)' > ~/ai_home/state/last_session.md
        [ -f ~/ai_home/state/current_plan.md ] || echo '(no plan yet)' > ~/ai_home/state/current_plan.md
        [ -f ~/ai_home/logs/history.md ] || echo '# AI History Log' > ~/ai_home/logs/history.md
        [ -f ~/ai_home/logs/consolidated_history.md ] || echo '# Consolidated History' > ~/ai_home/logs/consolidated_history.md
    "
    log_info "State files ready"
fi

# Step 4: Verify deployment
log_step "Verifying deployment..."

# Get status from server in one call (avoid eval issues with special chars)
SESSION_COUNTER=$(ssh "$SERVER" "cat ~/ai_home/state/session_counter.txt 2>/dev/null || echo 'N/A'")
CRON=$(ssh "$SERVER" "crontab -l 2>/dev/null | grep run_ai | head -1 || echo 'not set'")
TOKEN=$(ssh "$SERVER" "[ -f ~/.qwen/oauth_creds.json ] && echo 'present' || echo 'missing'")
AGENT_CONFIG=$(ssh "$SERVER" "[ -f ~/.config/mini-swe-agent/.env ] && echo 'present' || echo 'missing'")

echo ""
echo "========================================"
echo "   Deployment Summary"
echo "========================================"
echo ""
echo "  Session counter: $SESSION_COUNTER"
echo "  Cron job:        $CRON"
echo "  OAuth token:     $TOKEN"
echo "  Agent config:    $AGENT_CONFIG"
echo ""

# Warnings
if [ "$TOKEN" = "missing" ]; then
    log_warn "OAuth token missing! Copy from local machine or run qwen to authenticate."
fi

if [ "$AGENT_CONFIG" = "missing" ]; then
    log_warn "Agent config missing! Run: ssh $SERVER '~/sync-qwen-token.sh'"
fi

if [ "$CRON" = "not set" ]; then
    log_warn "Cron job not set! To enable auto-run every 3 minutes:"
    echo "  ssh $SERVER \"(crontab -l 2>/dev/null; echo '*/3 * * * * ~/run_ai.sh live-swe-agent >> ~/ai_home/logs/cron.log 2>&1') | crontab -\""
fi

echo ""
log_info "Deployment complete!"
