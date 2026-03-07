# Usage: project <url> [spec-file] [max_iterations]
#   project https://github.com/orgs/Org/projects/1          - spawn WezTerm with loop+tail panes
#   project https://github.com/orgs/Org/projects/1 spec.md  - same but with a spec file for context
#   project https://github.com/orgs/Org/projects/1 20       - same but with 20 max iterations
#   project --tail <url>                                      - tail the log for a running loop
#   project --session <url>                                     - follow Claude session JSONL across iterations
#   project --run <url> [spec-file] [max_iterations]          - run the loop directly (used internally)
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
if [ "${1:-}" = "--session" ]; then
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: project --session <url>"
    exit 1
  fi
  parse_project_url "$URL"
  STATE_NAME="project-${PROJECT_OWNER}-${PROJECT_NUMBER}"
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
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: project --tail <url>"
    exit 1
  fi
  parse_project_url "$URL"
  STATE_NAME="project-${PROJECT_OWNER}-${PROJECT_NUMBER}"
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

    OUTPUT=$(echo "$AGENT_PROMPT" | claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    kill $WATCHER_PID 2>/dev/null || true
    if [ -f "$STATE_DIR/.tail_pid" ]; then
      kill $(cat "$STATE_DIR/.tail_pid") 2>/dev/null || true
      rm -f "$STATE_DIR/.tail_pid"
    fi

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ All project issues processed!"
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
  echo "  project --tail https://github.com/orgs/MyOrg/projects/1"
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

echo "Spawning Project loop in new WezTerm window..."
echo "Project: $PROJECT_OWNER/$PROJECT_NUMBER"

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$URL" $EXTRA_ARGS)
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --session "$URL")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
