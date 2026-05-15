# Usage: loop <spec> [max_iterations]
#   loop myspec        - spawn a new WezTerm tab running the loop with specs/myspec.md
#   loop myspec 20     - same but with 20 max iterations
#   loop --follow spec [--raw] - follow Claude session JSONL across iterations
#   loop --run ...     - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  SPEC_NAME="${2:-}"
  if [ -z "$SPEC_NAME" ]; then
    echo "Usage: loop --follow <spec> [--raw]"
    exit 1
  fi
  exec claude-follow "$REPO/.state/$SPEC_NAME" "${3:-}"
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

  # Get Claude project directory from repo path
  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

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
  echo "Log file: $LOG_FILE"
  echo ""

  # Read and substitute __SPEC__ in loop.md
  AGENT_PROMPT=$(sed "s/__SPEC__/$SPEC_NAME/g" "$HOME/.claude/agents/loop.md")

  AGENT_PROMPT="$AGENT_PROMPT

$(cat "$HOME/.claude/agents/project-sleep.md")"

  SLEEP_COUNT=0

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    SESSION_ID=$(uuidgen)
    SESSION_FILE="$CLAUDE_PROJECT_DIR/$SESSION_ID.jsonl"
    echo "$SESSION_FILE" > "$STATE_DIR/current_session"
    echo "Session: $SESSION_ID" >> "$LOG_FILE"

    OUTPUT_FILE=$(mktemp)
    (echo "$AGENT_PROMPT" | claude --session-id "$SESSION_ID" 2>&1 | tee -a "$LOG_FILE" "$OUTPUT_FILE" >/dev/stderr) &
    CLAUDE_PID=$!

    # Monitor for Escape key — press Escape to skip to next iteration
    ESCAPED=false
    while kill -0 $CLAUDE_PID 2>/dev/null; do
      if read -t 0.5 -s -n1 key 2>/dev/null && [ "$key" = $'\e' ]; then
        echo ""
        echo "⏭ Escape pressed — skipping to next iteration..."
        kill $CLAUDE_PID 2>/dev/null || true
        wait $CLAUDE_PID 2>/dev/null || true
        ESCAPED=true
        break
      fi
    done

    if [ "$ESCAPED" = false ]; then
      wait $CLAUDE_PID 2>/dev/null || true
    fi

    OUTPUT=$(cat "$OUTPUT_FILE")
    rm -f "$OUTPUT_FILE"

    if [ "$ESCAPED" = true ]; then
      sleep 1
      continue
    fi

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ Done!"
      echo ""
      echo "Press Enter to restart loop..."
      read -r
      exec "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS"
    fi

    if echo "$OUTPUT" | grep -q "<promise>SLEEP</promise>"; then
      SLEEP_COUNT=$(claude-sleep "$SLEEP_COUNT")
      continue
    fi

    SLEEP_COUNT=0
    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Loop reached max iterations ($MAX_ITERATIONS) without completing all tasks."
  echo "Check $PROGRESS_FILE for status."
  echo ""
  echo "Press Enter to restart loop..."
  read -r
  exec "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS"
fi

# Validate arguments
SPEC_NAME="${1:-}"
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

# Spawn a new WezTerm window with the loop and session listener
echo "Spawning Claude loop..."
echo "Spec: $SPEC_NAME ($SPEC_FILE)"

STATE_DIR="$REPO/.state/$SPEC_NAME"
LOG_FILE="$STATE_DIR/loop.log"

# Ensure state dir and log file exist before spawning tail pane
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

exec mux-spawn "$REPO" "$SPEC_NAME" "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS" --- "$0" --follow "$SPEC_NAME"
