#!/bin/bash
#
# AI Agent Configuration
# Edit these values to customize the agent's behavior
#

# How often cron runs the agent (in minutes)
# This should match your crontab entry!
SESSION_INTERVAL_MINUTES=10

# Maximum session duration in seconds
# Set to 30 minutes to allow AI to complete longer tasks
# If a session runs longer than this, it will be killed
SESSION_TIMEOUT_SECONDS=1800  # 30 minutes

# Consolidation frequency (every N sessions)
# Default: 5 (consolidation happens at sessions 5, 10, 15, etc.)
# CONSOLIDATION_INTERVAL=5  # Not yet implemented, change in run_ai.sh if needed
