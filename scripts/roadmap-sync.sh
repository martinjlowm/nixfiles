# Usage: roadmap-sync
#   roadmap-sync          - spawn WezTerm with the roadmap sync agent
#   roadmap-sync --run    - run the agent directly (used internally)
#   roadmap-sync --apply  - run in apply mode (after approval)
set -e

PM_DIR="$HOME/projects/pm"
STATE_DIR="$PM_DIR/.state/roadmap-sync"

if [ ! -d "$PM_DIR" ]; then
  echo "Error: $PM_DIR does not exist"
  exit 1
fi

# Run the agent directly
if [ "${1:-}" = "--run" ] || [ "${1:-}" = "--apply" ]; then
  MODE="${1}"
  LOG_FILE="$STATE_DIR/loop.log"

  mkdir -p "$STATE_DIR"
  mkdir -p "$STATE_DIR/projects"

  grep -sq ".state/roadmap-sync" "$PM_DIR/.gitignore" 2>/dev/null || echo ".state/roadmap-sync/" >> "$PM_DIR/.gitignore"

  if [ ! -f "$STATE_DIR/progress.txt" ]; then
    echo "# Progress Log - Roadmap Sync" > "$STATE_DIR/progress.txt"
    echo "Started: $(date)" >> "$STATE_DIR/progress.txt"
    echo "---" >> "$STATE_DIR/progress.txt"
  fi

  echo "=== Run started: $(date) ===" >> "$LOG_FILE"

  AGENT_PROMPT=$(cat "$HOME/.claude/agents/roadmap-sync.md")

  if [ "$MODE" = "--apply" ]; then
    if [ ! -f "$STATE_DIR/report.json" ]; then
      echo "Error: No report found. Run 'roadmap-sync' first to generate the report."
      exit 1
    fi
    AGENT_PROMPT="$AGENT_PROMPT

---
The user has approved the changes in the report. Execute Phase 5 — apply the updates described in $STATE_DIR/report.json."
  fi

  SESSION_ID=$(uuidgen)

  echo "Starting Roadmap Sync"
  echo "Working directory: $PM_DIR"
  echo "State directory: $STATE_DIR"
  echo "Session: $SESSION_ID"
  echo ""

  OUTPUT=$(echo "$AGENT_PROMPT" | claude-pm --session-id "$SESSION_ID" --cwd "$PM_DIR" 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

  if echo "$OUTPUT" | grep -q "<promise>APPROVAL_REQUIRED</promise>"; then
    echo ""
    echo "📋 Review the report above."
    echo "To apply the changes, run: roadmap-sync --apply"
    exit 0
  fi

  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "✅ Roadmap sync complete!"
    exit 0
  fi

  echo ""
  echo "Run finished. Check $STATE_DIR for details."
  exit 0
fi

# Default: spawn in a new WezTerm window
echo "Spawning Roadmap Sync in new WezTerm window..."
echo "Working directory: $PM_DIR"

wezterm cli spawn --new-window --cwd "$PM_DIR" -- "$0" --run

echo "Roadmap sync started."
