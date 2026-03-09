# Usage: dependabot [max_iterations]
#   dependabot         - spawn a new WezTerm window running the Dependabot loop
#   dependabot 20      - same but with 20 max iterations
#   dependabot --tail   - tail the log for a running loop
#   dependabot --session - follow Claude session JSONL across iterations
#   dependabot --run ...  - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# Get Claude project directory from repo path
get_claude_project_dir() {
  local repo_path="$1"
  local encoded_path="${repo_path//\//-}"
  encoded_path="${encoded_path//./-}"
  echo "$HOME/.claude/projects/$encoded_path"
}

CLAUDE_PROJECT_DIR="$(get_claude_project_dir "$REPO")"

STATE_NAME="dependabot"

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--session" ]; then
  STATE_DIR="$REPO/.state/$STATE_NAME"
  CURRENT_SESSION_FILE="$STATE_DIR/current_session"

  echo "Watching for Claude sessions in $STATE_DIR..."

  # Wait for the state directory to be created by --run
  while [ ! -d "$STATE_DIR" ]; do sleep 1; done

  ACTIVE_SESSION=""
  TAIL_PID=""

  cleanup() {
    [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
    exit 0
  }
  trap cleanup INT TERM

  while true; do
    if [ -f "$CURRENT_SESSION_FILE" ]; then
      NEW_SESSION=$(cat "$CURRENT_SESSION_FILE")
      if [ "$NEW_SESSION" != "$ACTIVE_SESSION" ] && [ -f "$NEW_SESSION" ]; then
        [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
        ACTIVE_SESSION="$NEW_SESSION"
        echo ""
        echo "═══ Session: $(basename "$ACTIVE_SESSION") ═══"
        echo ""
        tail -f "$ACTIVE_SESSION" | jq --unbuffered -r '
          select(.message) |
          (if .message.content | type == "string" then
            .message.content
          else
            (.message.content // [] | map(.text // "") | join(""))
          end) as $text |
          select($text | length > 0) |
          "[\(.timestamp)] (\(.message.role)): \($text)"
        ' &
        TAIL_PID=$!
      fi
    fi
    sleep 2
  done
fi

# Tail the raw Claude session JSONL across iterations
if [ "${1:-}" = "--tail" ]; then
  STATE_DIR="$REPO/.state/$STATE_NAME"
  CURRENT_SESSION_FILE="$STATE_DIR/current_session"

  echo "Watching for Claude sessions in $STATE_DIR..."

  # Wait for the state directory to be created by --run
  while [ ! -d "$STATE_DIR" ]; do sleep 1; done

  ACTIVE_SESSION=""
  TAIL_PID=""

  cleanup() {
    [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
    exit 0
  }
  trap cleanup INT TERM

  while true; do
    if [ -f "$CURRENT_SESSION_FILE" ]; then
      NEW_SESSION=$(cat "$CURRENT_SESSION_FILE")
      if [ "$NEW_SESSION" != "$ACTIVE_SESSION" ] && [ -f "$NEW_SESSION" ]; then
        [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
        ACTIVE_SESSION="$NEW_SESSION"
        echo ""
        echo "═══ Session: $(basename "$ACTIVE_SESSION") ═══"
        echo ""
        tail -f "$ACTIVE_SESSION" &
        TAIL_PID=$!
      fi
    fi
    sleep 2
  done
fi

# Run the loop directly (used internally by WezTerm spawn)
if [ "${1:-}" = "--run" ]; then
  shift
  MAX_ITERATIONS=${1:-10}
  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

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

  TIMESTAMP_MARKER="$STATE_DIR/.timestamp_marker"
  SESSION_LOG="$STATE_DIR/session.log"

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    touch "$TIMESTAMP_MARKER"
    sleep 1

    (
      SESSION_FILE=""
      for _ in $(seq 1 30); do
        if [ -d "$CLAUDE_PROJECT_DIR" ]; then
          SESSION_FILE=$(find "$CLAUDE_PROJECT_DIR" -name "*.jsonl" -newer "$TIMESTAMP_MARKER" -type f 2>/dev/null | head -1)
          if [ -n "$SESSION_FILE" ]; then
            echo "$SESSION_FILE" > "$STATE_DIR/current_session"
            echo "Session file: $(basename "$SESSION_FILE")" >> "$LOG_FILE"
            tail -f "$SESSION_FILE" >> "$SESSION_LOG" 2>/dev/null &
            TAIL_PID=$!
            echo $TAIL_PID > "$STATE_DIR/.tail_pid"
            break
          fi
        fi
        sleep 1
      done
    ) &
    WATCHER_PID=$!

    OUTPUT=$(echo "$AGENT_PROMPT" | safehouse claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    kill $WATCHER_PID 2>/dev/null || true
    if [ -f "$STATE_DIR/.tail_pid" ]; then
      kill $(cat "$STATE_DIR/.tail_pid") 2>/dev/null || true
      rm -f "$STATE_DIR/.tail_pid"
    fi

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

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --session)

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
