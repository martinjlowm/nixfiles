# Usage: github-issues <url> [max_iterations]
#   github-issues 'https://github.com/Org/Repo/issues?q=...'       - spawn WezTerm with loop+tail panes
#   github-issues 'https://github.com/Org/Repo/issues?q=...' 20    - same but with 20 max iterations
#   github-issues --tail <url>                                       - tail the log for a running loop
#   github-issues --session <url>                                      - follow Claude session JSONL across iterations
#   github-issues --run <url> [max_iterations]                       - run the loop directly (used internally)
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

# URL-decode: + → space, %XX → byte
urldecode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

# Parse GitHub issues URL into owner, repo, and search query
parse_issues_url() {
  local url="$1"
  local base_url="${url%%\?*}"
  local query_string="${url#*\?}"

  # If no ?, query_string equals url
  if [ "$query_string" = "$url" ]; then
    query_string=""
  fi

  if [[ "$base_url" =~ github\.com/([^/]+)/([^/]+)/issues$ ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
  else
    echo "Error: Invalid GitHub issues URL: $url"
    echo ""
    echo "Expected format:"
    echo "  https://github.com/<owner>/<repo>/issues?q=<filter>"
    echo ""
    echo "Example:"
    echo "  github-issues 'https://github.com/Org/Repo/issues?q=is%3Aissue+state%3Aopen+label%3Abug'"
    exit 1
  fi

  # Extract and decode the q= parameter
  SEARCH_QUERY=""
  if [ -n "$query_string" ]; then
    local q_value
    q_value=$(echo "$query_string" | grep -o 'q=[^&]*' | head -1 | cut -d= -f2-)
    if [ -n "$q_value" ]; then
      SEARCH_QUERY=$(urldecode "$q_value")
    fi
  fi

  # Derive state name from owner, repo, and a hash of the query
  local query_hash
  query_hash=$(printf '%s' "$SEARCH_QUERY" | shasum -a 256 | cut -c1-8)
  STATE_NAME="github-issues-${REPO_OWNER}-${REPO_NAME}-${query_hash}"
}

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--session" ]; then
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: github-issues --session <url>"
    exit 1
  fi
  parse_issues_url "$URL"
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
    echo "Usage: github-issues --tail <url>"
    exit 1
  fi
  parse_issues_url "$URL"
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
  MAX_ITERATIONS=${1:-10}

  parse_issues_url "$URL"

  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

  mkdir -p "$STATE_DIR"

  grep -sq ".state/$STATE_NAME" "$REPO/.gitignore" || echo ".state/$STATE_NAME/" >> "$REPO/.gitignore"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - GitHub Issues: $REPO_OWNER/$REPO_NAME" > "$PROGRESS_FILE"
    echo "Search: $SEARCH_QUERY" >> "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  echo "=== Loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting GitHub Issues Loop"
  echo "Repo: $REPO_OWNER/$REPO_NAME"
  echo "Search: $SEARCH_QUERY"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  # Read template and substitute placeholders using bash parameter substitution
  # (safe for queries containing |, /, ", etc.)
  AGENT_TEMPLATE=$(cat "$HOME/.claude/agents/github-issues.md")
  AGENT_PROMPT="${AGENT_TEMPLATE//__REPO_OWNER__/$REPO_OWNER}"
  AGENT_PROMPT="${AGENT_PROMPT//__REPO_NAME__/$REPO_NAME}"
  AGENT_PROMPT="${AGENT_PROMPT//__SEARCH_QUERY__/$SEARCH_QUERY}"
  AGENT_PROMPT="${AGENT_PROMPT//__STATE_NAME__/$STATE_NAME}"

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

    OUTPUT=$(echo "$AGENT_PROMPT" | safehouse -- claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    kill $WATCHER_PID 2>/dev/null || true
    if [ -f "$STATE_DIR/.tail_pid" ]; then
      kill $(cat "$STATE_DIR/.tail_pid") 2>/dev/null || true
      rm -f "$STATE_DIR/.tail_pid"
    fi

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ All matching issues processed!"
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
  echo "Usage: github-issues <url> [max_iterations]"
  echo ""
  echo "Arguments:"
  echo "  url             GitHub issues URL with query filter"
  echo "  max_iterations  Maximum loop iterations (default: 10)"
  echo ""
  echo "Examples:"
  echo "  github-issues 'https://github.com/Org/Repo/issues?q=is%3Aissue+state%3Aopen+label%3Abug'"
  echo "  github-issues 'https://github.com/Org/Repo/issues?q=is%3Aissue+state%3Aopen' 20"
  echo "  github-issues --tail 'https://github.com/Org/Repo/issues?q=...'"
  exit 1
fi

parse_issues_url "$URL"
MAX_ITERATIONS=${2:-10}

STATE_DIR="$REPO/.state/$STATE_NAME"
LOG_FILE="$STATE_DIR/loop.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "Spawning GitHub Issues loop in new WezTerm window..."
echo "Repo: $REPO_OWNER/$REPO_NAME"
echo "Search: $SEARCH_QUERY"

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$URL" "$MAX_ITERATIONS")
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --session "$URL")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
