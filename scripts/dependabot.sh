# Usage: dependabot [max_iterations]
#   dependabot             - spawn a new WezTerm window running the Dependabot loop
#   dependabot 20          - same but with 20 max iterations
#   dependabot --follow [--raw] - follow Claude session JSONL across iterations
#   dependabot --run ...   - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"
STATE_NAME="dependabot"

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  exec claude-follow "$REPO/.state/$STATE_NAME" "${2:-}"
fi

# Run the loop directly (used internally by WezTerm spawn)
if [ "${1:-}" = "--run" ]; then
  shift
  MAX_ITERATIONS=${1:-10}
  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

  mkdir -p "$STATE_DIR"

  grep -sq ".state/$STATE_NAME" "$REPO/.gitignore" || echo ".state/$STATE_NAME/" >> "$REPO/.gitignore"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - Dependabot PRs" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  echo "=== Loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting Dependabot Loop"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  AGENT_PROMPT=$(cat "$HOME/.claude/agents/dependabot.md")

  SESSION_LOG="$STATE_DIR/session.log"

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    SESSION_ID=$(uuidgen)
    SESSION_FILE="$CLAUDE_PROJECT_DIR/$SESSION_ID.jsonl"
    echo "$SESSION_FILE" > "$STATE_DIR/current_session"
    echo "Session: $SESSION_ID" >> "$LOG_FILE"

    (
      while [ ! -f "$SESSION_FILE" ]; do sleep 0.5; done
      tail -f "$SESSION_FILE" >> "$SESSION_LOG" 2>/dev/null
    ) &
    TAIL_PID=$!

    OUTPUT=$(echo "$AGENT_PROMPT" | claude --session-id "$SESSION_ID" 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    kill $TAIL_PID 2>/dev/null || true

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ All Dependabot PRs processed!"
      echo ""
      echo "Press Enter to close this tab..."
      read -r
      exit 0
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Loop reached max iterations ($MAX_ITERATIONS)."
  echo "Check $PROGRESS_FILE for status."
  echo ""
  echo "Press Enter to close this tab..."
  read -r
  exit 1
fi

# Default: spawn in a new WezTerm window
MAX_ITERATIONS=${1:-10}
STATE_DIR="$REPO/.state/$STATE_NAME"
LOG_FILE="$STATE_DIR/loop.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "Spawning Dependabot loop in new WezTerm window..."

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$MAX_ITERATIONS")
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --follow)

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
