# Usage: loop <spec> [max_iterations]
#   loop myspec        - spawn a new WezTerm tab running the loop with specs/myspec.md
#   loop myspec 20     - same but with 20 max iterations
#   loop --tail spec   - tail the log for a running loop
#   loop --session spec - follow Claude session JSONL across iterations
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

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--session" ]; then
  SPEC_NAME="${2:-}"
  if [ -z "$SPEC_NAME" ]; then
    echo "Usage: loop --session <spec>"
    exit 1
  fi
  STATE_DIR="$REPO/.state/$SPEC_NAME"
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
  SPEC_NAME="${2:-}"
  if [ -z "$SPEC_NAME" ]; then
    echo "Usage: loop --tail <spec>"
    exit 1
  fi
  STATE_DIR="$REPO/.state/$SPEC_NAME"
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

    OUTPUT=$(echo "$AGENT_PROMPT" | safehouse -- claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

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

# Spawn a new WezTerm window with the loop and session listener
echo "Spawning Claude loop in new WezTerm window..."
echo "Spec: $SPEC_NAME ($SPEC_FILE)"
echo "Session: $SESSION_NAME"

STATE_DIR="$REPO/.state/$SPEC_NAME"
LOG_FILE="$STATE_DIR/loop.log"

# Ensure state dir and log file exist before spawning tail pane
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

# Spawn the loop in a new window (top pane)
LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS")
sleep 1

# Split for the session tail (bottom pane)
SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --session "$SPEC_NAME")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
