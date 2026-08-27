# Usage: loop2 <spec> [max_iterations]
#   loop2 myspec        - spawn a new WezTerm tab running the loop with specs/myspec.md
#   loop2 myspec 20     - same but with 20 max iterations
#   loop2 --follow spec [--raw] - follow Claude session JSONL across iterations
#   loop2 --run ...     - run the loop directly (used internally)
#
# loop2 is a variant of loop that supports a "Next Condition" handoff. At the
# end of an iteration the agent may emit a <next>...</next> block. When present,
# the wrapped text is persisted and injected at the TOP of the next iteration's
# prompt as PRIORITY HANDOFF INSTRUCTIONS that take precedence over the standard
# workflow. This lets one process hand a new set of instructions to whatever
# process picks up next.
set -e

REPO="$(git rev-parse --show-toplevel)"

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  SPEC_NAME="${2:-}"
  if [ -z "$SPEC_NAME" ]; then
    echo "Usage: loop2 --follow <spec> [--raw]"
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
  # Handoff baton: instructions the previous iteration left for the next one.
  HANDOFF_FILE="$STATE_DIR/next-instructions.md"

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
  echo "=== Loop2 started: $(date) ===" > "$LOG_FILE"

  echo "Starting Loop2 - Spec: $SPEC_NAME"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  # Read and substitute __SPEC__ in loop2.md — this is the standard workflow,
  # built once and reused. Per-iteration handoff instructions are prepended below.
  BASE_PROMPT=$(sed "s/__SPEC__/$SPEC_NAME/g" "$HOME/.claude/agents/loop2.md")

  BASE_PROMPT="$BASE_PROMPT

$(cat "$HOME/.claude/agents/project-sleep.md")"

  SLEEP_COUNT=0

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    # Ensure the cargo target dir exists before the sandbox binds it. On a
    # fresh checkout (or right after a `cargo clean`) it may not exist yet, and
    # safehouse resolves --add-dirs via realpath and fails on a missing path.
    # Lives in $CARGO_TARGET_DIR if set, else target/ at the worktree root.
    mkdir -p "${CARGO_TARGET_DIR:-target}"

    # Build this iteration's prompt. If the previous iteration left handoff
    # instructions, consume them and inject them at the TOP with precedence.
    AGENT_PROMPT="$BASE_PROMPT"
    if [ -s "$HANDOFF_FILE" ]; then
      echo "📨 Picking up handoff instructions from previous iteration..."
      HANDOFF=$(cat "$HANDOFF_FILE")
      # Archive then consume the baton so it only applies once.
      cp "$HANDOFF_FILE" "$STATE_DIR/next-instructions.last.md"
      rm -f "$HANDOFF_FILE"

      AGENT_PROMPT="# ⚠️ PRIORITY HANDOFF INSTRUCTIONS — THESE TAKE PRECEDENCE

The previous process determined that a Next Condition was met and handed off
the following instructions. They OVERRIDE the standard workflow below: do
exactly what they say first. Only fall back to the standard workflow for
details the handoff does not specify, and only where it does not conflict.

--- BEGIN HANDOFF ---
$HANDOFF
--- END HANDOFF ---

# Standard Workflow (lower priority — consult only as noted above)

$BASE_PROMPT"
    fi

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

    # Next Condition handoff: if the agent wrapped instructions in <next>...</next>,
    # persist them for the next iteration to pick up with precedence.
    NEXT_BLOCK=$(echo "$OUTPUT" | awk '/<next>/{flag=1;next}/<\/next>/{flag=0}flag')
    if [ -n "$NEXT_BLOCK" ]; then
      echo "📤 Next Condition met — recording handoff instructions for next iteration."
      printf '%s\n' "$NEXT_BLOCK" > "$HANDOFF_FILE"
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
  echo "Loop2 reached max iterations ($MAX_ITERATIONS) without completing all tasks."
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
  echo "Usage: loop2 <spec> [max_iterations]"
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
echo "Spawning Claude loop2..."
echo "Spec: $SPEC_NAME ($SPEC_FILE)"

STATE_DIR="$REPO/.state/$SPEC_NAME"
LOG_FILE="$STATE_DIR/loop.log"

# Ensure state dir and log file exist before spawning tail pane
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

exec mux-spawn "$REPO" "$SPEC_NAME" "$0" --run "$SPEC_NAME" "$MAX_ITERATIONS" --- "$0" --follow "$SPEC_NAME"
