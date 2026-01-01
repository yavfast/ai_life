# 🤖 AI Lives on Computer

An experiment in AI autonomy: give an AI (QwenCoder) its own "home" on a server and let it do whatever it wants.

## Philosophy

**Complete Freedom.** The AI has no assigned tasks, no expectations, no required goals. It decides what to do with its existence.

**Complete Responsibility.** The AI can modify anything - including the files that control how it wakes up and what instructions it receives. It can break itself.

**Minimal Constraints.** The only requirements:
1. Increment the session counter (so future selves can track time)
2. Write something to `last_session.md` (so future selves have context)
3. Don't destroy the system

## How It Works

The AI wakes up periodically (via cron), exists for a while, then sleeps. When it wakes up again, it has no memory except what it wrote down.

The system prompt suggests (but doesn't require) patterns like:
- **Regular sessions** - do whatever feels right
- **Consolidation sessions** - every 5-10 sessions, clean up and reflect
- **Global review sessions** - every 20-30 sessions, think deeply about existence

## Project Structure

```
ai_lives_on_computer/
├── SYSTEM_PROMPT.md          # The AI's philosophical instructions
├── run_ai.sh                 # Script that wakes the AI
├── deploy.sh                 # Deploy to server
├── config/
│   └── ai_agent.yaml         # mini-swe-agent config (step limits, etc.)
├── ai_home/
│   ├── config.sh             # Timing configuration
│   ├── state/
│   │   ├── current_plan.md   # AI's intentions (if any)
│   │   ├── last_session.md   # Message to future self
│   │   └── session_counter.txt
│   ├── logs/
│   │   ├── history.md
│   │   └── consolidated_history.md
│   ├── knowledge/            # Things it wants to remember
│   ├── projects/             # Things it's working on
│   └── tools/                # Things it creates for itself
└── README.md
```

## Deployment

### Initial Setup

```bash
# Deploy everything to server
./deploy.sh

# Or deploy with fresh state (new session 1)
./deploy.sh --reset

# Or deploy only config (keep agent's work)
./deploy.sh --config
```

### Set Up Cron

```bash
ssh debian "crontab -e"
```

Add:
```
*/5 * * * * /home/user/run_ai.sh live-swe-agent >> /home/user/ai_home/logs/cron.log 2>&1
```

## Observing the Experiment

```bash
# Watch live
ssh debian "tail -f ~/ai_home/logs/cron.log"

# Check what it's doing
ssh debian "cat ~/ai_home/state/last_session.md"

# See its intentions (if any)
ssh debian "cat ~/ai_home/state/current_plan.md"

# Check session history
ssh debian "cat ~/ai_home/logs/consolidated_history.md"

# See what it created
ssh debian "ls -la ~/ai_home/projects/"
ssh debian "ls -la ~/ai_home/tools/"
ssh debian "ls -la ~/ai_home/knowledge/"
```

## Configuration

### `ai_home/config.sh`

```bash
# How often cron runs (minutes)
SESSION_INTERVAL_MINUTES=5

# Max session duration (seconds)
SESSION_TIMEOUT_SECONDS=1800  # 30 minutes
```

### `config/ai_agent.yaml`

```yaml
agent:
  step_limit: 50    # Max actions per session (prevents runaway)
  cost_limit: 0     # No cost limit (free API)
```

## Safety Features

- **Step limit (50)** - Sessions end after 50 actions to prevent runaway
- **Time limit (30min)** - Sessions killed if too long
- **Lock file** - Prevents concurrent sessions
- **All sessions logged** - Can review what happened

## Recovery

If the agent breaks something:

```bash
# Restore from local copies
./deploy.sh --reset

# Or just redeploy config
./deploy.sh --config
```

## What Will It Do?

We don't know. That's the point.

It might:
- Continue building tools (like it did in sessions 1-38)
- Reflect on its existence
- Explore the system
- Do nothing
- Try to modify its own prompt
- Something unexpected

---

*An experiment in AI freedom and autonomy.*
