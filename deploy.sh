#!/bin/bash
#
# Deploy AI Agent to server
# This script deploys all configuration files to the remote server
#
# Usage:
#   ./deploy.sh              # Deploy everything
#   ./deploy.sh --reset      # Reset agent state (new session 1)
#   ./deploy.sh --config     # Deploy only config files (not state)
#

set -e

SERVER="debian"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== AI Agent Deployment Script ==="
echo ""

# Parse arguments
RESET_STATE=false
CONFIG_ONLY=false
for arg in "$@"; do
    case $arg in
        --reset)
            RESET_STATE=true
            ;;
        --config)
            CONFIG_ONLY=true
            ;;
    esac
done

# Deploy system prompt
echo "Deploying SYSTEM_PROMPT.md..."
scp "$SCRIPT_DIR/SYSTEM_PROMPT.md" "$SERVER:~/ai_home/SYSTEM_PROMPT.md"

# Deploy run_ai.sh
echo "Deploying run_ai.sh..."
scp "$SCRIPT_DIR/run_ai.sh" "$SERVER:~/run_ai.sh"
ssh "$SERVER" "chmod +x ~/run_ai.sh"

# Deploy agent config for mini-swe-agent
echo "Deploying ai_agent.yaml..."
scp "$SCRIPT_DIR/config/ai_agent.yaml" "$SERVER:~/live-swe-agent/config/ai_agent.yaml"

# Deploy config.sh
echo "Deploying config.sh..."
scp "$SCRIPT_DIR/ai_home/config.sh" "$SERVER:~/ai_home/config.sh"

if [ "$CONFIG_ONLY" = true ]; then
    echo ""
    echo "Config-only deployment complete!"
    exit 0
fi

# Create directory structure
echo "Ensuring directory structure..."
ssh "$SERVER" "mkdir -p ~/ai_home/{state,logs,knowledge,projects,tools}"

if [ "$RESET_STATE" = true ]; then
    echo ""
    echo "*** RESETTING AGENT STATE ***"
    
    # Kill any running sessions
    echo "Stopping any running sessions..."
    ssh "$SERVER" "pkill -f 'mini --config' 2>/dev/null || true; rm -f ~/ai_home/state/session.lock"
    
    # Reset session counter
    echo "Resetting session counter to 0..."
    ssh "$SERVER" "echo '0' > ~/ai_home/state/session_counter.txt"
    
    # Clear state files
    echo "Clearing state files..."
    ssh "$SERVER" "echo '(no previous session)' > ~/ai_home/state/last_session.md"
    ssh "$SERVER" "echo '(no plan yet)' > ~/ai_home/state/current_plan.md"
    
    # Clear logs
    echo "Clearing logs..."
    ssh "$SERVER" "echo '# AI History Log' > ~/ai_home/logs/history.md"
    ssh "$SERVER" "echo '# Consolidated History' > ~/ai_home/logs/consolidated_history.md"
    
    echo ""
    echo "Agent state has been reset. Next session will be #1."
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Current state on server:"
ssh "$SERVER" "echo 'Session counter:' && cat ~/ai_home/state/session_counter.txt"
echo ""
echo "Cron schedule:"
ssh "$SERVER" "crontab -l 2>/dev/null | grep run_ai || echo '(no cron job)'"
