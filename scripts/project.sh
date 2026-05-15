# Usage: project <url> [spec-file] [max_iterations]
#   project https://github.com/orgs/Org/projects/1          - spawn WezTerm with loop+tail panes
#   project https://github.com/orgs/Org/projects/1 spec.md  - same but with a spec file for context
#   project https://github.com/orgs/Org/projects/1 20       - same but with 20 max iterations
#   project --follow <url> [--raw]                            - follow Claude session JSONL
#   project --run <url> [spec-file] [max_iterations]          - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# Parse project URL into owner and number
parse_project_url() {
  local url="$1"
  if [[ "$url" =~ github\.com/(orgs|users)/([^/]+)/projects/([0-9]+)$ ]]; then
    PROJECT_OWNER="${BASH_REMATCH[2]}"
    PROJECT_NUMBER="${BASH_REMATCH[3]}"
  else
    echo "Error: Invalid GitHub project URL: $url"
    echo ""
    echo "Expected format:"
    echo "  https://github.com/orgs/<org>/projects/<number>"
    echo "  https://github.com/users/<user>/projects/<number>"
    exit 1
  fi
}

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: project --follow <url> [--raw]"
    exit 1
  fi
  parse_project_url "$URL"
  exec claude-follow "$REPO/.state/project-${PROJECT_OWNER}-${PROJECT_NUMBER}" "${3:-}"
fi

# Run the loop directly (used internally by WezTerm spawn)
if [ "${1:-}" = "--run" ]; then
  shift
  URL="$1"
  shift

  parse_project_url "$URL"
  STATE_NAME="project-${PROJECT_OWNER}-${PROJECT_NUMBER}"

  # Detect spec file vs max_iterations
  SPEC_FILE="NONE"
  MAX_ITERATIONS=10
  if [ -n "${1:-}" ]; then
    if [ -f "$1" ]; then
      SPEC_FILE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
      shift
      MAX_ITERATIONS=${1:-10}
    else
      MAX_ITERATIONS=${1:-10}
    fi
  fi

  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

  mkdir -p "$STATE_DIR"

  grep -sq ".state/$STATE_NAME" "$REPO/.gitignore" || echo ".state/$STATE_NAME/" >> "$REPO/.gitignore"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - Project $PROJECT_OWNER/$PROJECT_NUMBER" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  echo "=== Loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting Project Loop"
  echo "Project: $PROJECT_OWNER/$PROJECT_NUMBER"
  echo "Spec file: $SPEC_FILE"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  # Read and substitute placeholders in project.md
  AGENT_PROMPT=$(sed \
    -e "s|__PROJECT_OWNER__|$PROJECT_OWNER|g" \
    -e "s|__PROJECT_NUMBER__|$PROJECT_NUMBER|g" \
    -e "s|__STATE_NAME__|$STATE_NAME|g" \
    -e "s|__SPEC_FILE__|$SPEC_FILE|g" \
    "$HOME/.claude/agents/project.md")

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
      echo "✅ All project issues processed!"
      echo ""
      echo "Press Enter to restart loop..."
      read -r
      if [ "$SPEC_FILE" != "NONE" ]; then
        exec "$0" --run "$URL" "$SPEC_FILE" "$MAX_ITERATIONS"
      else
        exec "$0" --run "$URL" "$MAX_ITERATIONS"
      fi
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
  echo "Loop reached max iterations ($MAX_ITERATIONS)."
  echo "Check $PROGRESS_FILE for status."
  echo ""
  echo "Press Enter to restart loop..."
  read -r
  if [ "$SPEC_FILE" != "NONE" ]; then
    exec "$0" --run "$URL" "$SPEC_FILE" "$MAX_ITERATIONS"
  else
    exec "$0" --run "$URL" "$MAX_ITERATIONS"
  fi
fi

# Default: parse args and spawn in a new WezTerm window
URL="${1:-}"

if [ -z "$URL" ]; then
  echo "Usage: project <url> [spec-file] [max_iterations]"
  echo ""
  echo "Arguments:"
  echo "  url             GitHub project URL (orgs or users)"
  echo "  spec-file       Optional spec file for additional context"
  echo "  max_iterations  Maximum loop iterations (default: 10)"
  echo ""
  echo "Examples:"
  echo "  project https://github.com/orgs/MyOrg/projects/1"
  echo "  project https://github.com/users/me/projects/2 spec.md"
  echo "  project https://github.com/orgs/MyOrg/projects/1 spec.md 20"
  echo "  project --follow https://github.com/orgs/MyOrg/projects/1"
  exit 1
fi

parse_project_url "$URL"
STATE_NAME="project-${PROJECT_OWNER}-${PROJECT_NUMBER}"

# Collect remaining args to forward
EXTRA_ARGS=""
shift
if [ -n "${1:-}" ]; then
  if [ -f "$1" ]; then
    EXTRA_ARGS="$1"
    shift
    if [ -n "${1:-}" ]; then
      EXTRA_ARGS="$EXTRA_ARGS $1"
    fi
  else
    EXTRA_ARGS="$1"
  fi
fi

STATE_DIR="$REPO/.state/$STATE_NAME"
LOG_FILE="$STATE_DIR/loop.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "Spawning Project loop..."
echo "Project: $PROJECT_OWNER/$PROJECT_NUMBER"

exec mux-spawn "$REPO" "$STATE_NAME" "$0" --run "$URL" $EXTRA_ARGS --- "$0" --follow "$URL"
