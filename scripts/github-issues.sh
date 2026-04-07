# Usage: github-issues <url> [max_iterations]
#   github-issues 'https://github.com/Org/Repo/issues?q=...'       - spawn WezTerm with loop+tail panes
#   github-issues 'https://github.com/Org/Repo/issues?q=...' 20    - same but with 20 max iterations
#   github-issues --follow <url> [--raw]                             - follow Claude session JSONL
#   github-issues --run <url> [max_iterations]                       - run the loop directly (used internally)
set -e

# Extract --with-sleep <min> if present
SLEEP_MIN=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --with-sleep) SLEEP_MIN="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

REPO="$(git rev-parse --show-toplevel)"

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
if [ "${1:-}" = "--follow" ]; then
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: github-issues --follow <url> [--raw]"
    exit 1
  fi
  parse_issues_url "$URL"
  exec claude-follow "$REPO/.state/$STATE_NAME" "${3:-}"
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

  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

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

  if [ -n "$SLEEP_MIN" ]; then
    AGENT_PROMPT="$AGENT_PROMPT

$(cat "$HOME/.claude/agents/project-sleep.md")"
  fi

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
      echo "✅ All matching issues processed!"
      echo ""
      echo "Press Enter to close this tab..."
      read -r
      exit 0
    fi

    if [ -n "$SLEEP_MIN" ] && echo "$OUTPUT" | \
        grep -q "<promise>SLEEP</promise>"
    then
      echo "💤 Blocked on CI/reviews. Sleeping $SLEEP_MIN minutes..."
      sleep $((SLEEP_MIN * 60))
      echo "Resuming after sleep."
      continue
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
  echo "  github-issues --follow 'https://github.com/Org/Repo/issues?q=...'"
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

SLEEP_ARGS=()
if [ -n "$SLEEP_MIN" ]; then
  SLEEP_ARGS=(--with-sleep "$SLEEP_MIN")
fi

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" "${SLEEP_ARGS[@]}" --run "$URL" "$MAX_ITERATIONS")
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --follow "$URL")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
