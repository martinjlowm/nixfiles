# Usage: loop <spec> [max_iterations]
#   loop myspec        - spawn a new WezTerm tab running the loop with specs/myspec.md
#   loop myspec 20     - same but with 20 max iterations
#   loop --tail spec   - tail the log for a running loop
#   loop --session     - tail the latest Claude session JSONL
#   loop --run ...     - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# Get Claude project directory from repo path
# /Users/foo/projects/bar -> ~/.claude/projects/-Users-foo-projects-bar
get_claude_project_dir() {
  local repo_path="$1"
  local encoded_path="${repo_path//\//-}"
  encoded_path="${encoded_path//./-}"
  echo "$HOME/.claude/projects/$encoded_path"
}

CLAUDE_PROJECT_DIR="$(get_claude_project_dir "$REPO")"

# Tail the latest Claude session JSONL
if [ "${1:-}" = "--session" ]; then
  if [ ! -d "$CLAUDE_PROJECT_DIR" ]; then
    echo "No Claude project directory found: $CLAUDE_PROJECT_DIR"
    exit 1
  fi

  # Find the newest JSONL file (by modification time)
  LATEST_SESSION=$(ls -t "$CLAUDE_PROJECT_DIR"/*.jsonl 2>/dev/null | head -1)

  if [ -z "$LATEST_SESSION" ]; then
    echo "No session files found in $CLAUDE_PROJECT_DIR"
    exit 1
  fi

  echo "Tailing latest session: $LATEST_SESSION"
  exec tail -f "$LATEST_SESSION" | jq --unbuffered -r '
    select(.message) |
    (if .message.content | type == "string" then
      .message.content
    else
      (.message.content // [] | map(.text // "") | join(""))
    end) as $text |
    select($text | length > 0) |
    "[\(.timestamp)] (\(.message.role)): \($text)"
  '
fi

# Tail the log for a spec
if [ "${1:-}" = "--tail" ]; then
  SPEC_NAME="$2"
  if [ -z "$SPEC_NAME" ]; then
    echo "Usage: loop --tail <spec>"
    exit 1
  fi
  LOG_FILE="$REPO/.state/$SPEC_NAME/loop.log"
  if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found: $LOG_FILE"
    exit 1
  fi
  exec tail -f "$LOG_FILE"
fi

# If --run flag, execute the loop directly
if [ "${1:-}" = "--run" ]; then
  shift
  SPEC_NAME="$1"
  MAX_ITERATIONS=${2:-10}
  SPEC_FILE="$REPO/specs/$SPEC_NAME.md"
  STATE_DIR="$REPO/.state/$SPEC_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"
  SESSION_NAME="claude-loop-$SPEC_NAME"

  # Ensure state directory exists
  mkdir -p "$STATE_DIR"

  grep -sq ".state/$SPEC_NAME" "$REPO/.gitignore" || echo ".state/$SPEC_NAME/" >> "$REPO/.gitignore"

  # Initialize progress file if it doesn't exist
  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - $SPEC_NAME" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  # Initialize log file
  echo "=== Loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting Loop - Spec: $SPEC_NAME"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Session: $SESSION_NAME"
  echo "Log file: $LOG_FILE"
  echo ""

  # Read and substitute __SPEC__ in loop.md
  AGENT_PROMPT=$(sed "s/__SPEC__/$SPEC_NAME/g" "$HOME/.claude/agents/loop.md")

  # Create a timestamp marker file for tracking session files
  TIMESTAMP_MARKER="$STATE_DIR/.timestamp_marker"
  SESSION_LOG="$STATE_DIR/session.log"

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    # Touch marker file before starting Claude to identify new session files
    touch "$TIMESTAMP_MARKER"
    sleep 1  # Ensure timestamp difference

    # Start a background watcher to find and tail the session file
    (
      # Wait for Claude to create the session file
      SESSION_FILE=""
      for _ in $(seq 1 30); do
        if [ -d "$CLAUDE_PROJECT_DIR" ]; then
          SESSION_FILE=$(find "$CLAUDE_PROJECT_DIR" -name "*.jsonl" -newer "$TIMESTAMP_MARKER" -type f 2>/dev/null | head -1)
          if [ -n "$SESSION_FILE" ]; then
            echo "$SESSION_FILE" > "$STATE_DIR/current_session"
            echo "Session file: $(basename "$SESSION_FILE")" >> "$LOG_FILE"
            # Tail the session file to the session log
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

    OUTPUT=$(echo "$AGENT_PROMPT" | claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    # Stop the background watcher and tail
    kill $WATCHER_PID 2>/dev/null || true
    if [ -f "$STATE_DIR/.tail_pid" ]; then
      kill $(cat "$STATE_DIR/.tail_pid") 2>/dev/null || true
      rm -f "$STATE_DIR/.tail_pid"
    fi

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ Done!"
      echo ""
      echo "Press Enter to close this tab..."
      read -r
      exit 0
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Loop reached max iterations ($MAX_ITERATIONS) without completing all tasks."
  echo "Check $PROGRESS_FILE for status."
  echo ""
  echo "Press Enter to close this tab..."
  read -r
  exit 1
fi

# Validate arguments
SPEC_NAME="$1"
MAX_ITERATIONS=${2:-10}

if [ -z "$SPEC_NAME" ]; then
  echo "Usage: loop <spec> [max_iterations]"
  echo ""
  echo "Arguments:"
  echo "  spec            Name of the spec file (without .md extension)"
  echo "  max_iterations  Maximum loop iterations (default: 10)"
  echo ""
  echo "The spec file should be at: specs/<spec>.md"
  exit 1
fi

SPEC_FILE="$REPO/specs/$SPEC_NAME.md"
if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: Spec file not found: $SPEC_FILE"
  echo ""
  echo "Create the spec file first:"
  echo "  mkdir -p $REPO/specs"
  echo "  \$EDITOR $SPEC_FILE"
  exit 1
fi

SESSION_NAME="claude-loop-$SPEC_NAME"

# Spawn a new WezTerm tab with the loop
echo "Spawning Claude loop in new WezTerm tab..."
echo "Spec: $SPEC_NAME ($SPEC_FILE)"
echo "Session: $SESSION_NAME"

PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS")

STATE_DIR="$REPO/.state/$SPEC_NAME"
LOG_FILE="$STATE_DIR/loop.log"

echo ""
echo "Loop started in pane: $PANE_ID"
echo "Log file: $LOG_FILE"
echo ""
echo "To monitor output:"
echo "  loop --tail $SPEC_NAME     # tail loop log"
echo "  loop --session             # tail latest Claude session JSONL"
echo ""
echo "To focus the pane:"
echo "  wezterm cli activate-pane --pane-id $PANE_ID"
