# Usage: pr-review <url> [max_iterations]
#   pr-review 'https://github.com/Org/Repo/pulls?q=...'       - spawn WezTerm with loop+tail panes
#   pr-review 'https://github.com/Org/Repo/pulls?q=...' 20    - same but with 20 max iterations
#   pr-review --follow <url> [--raw]                            - follow Claude session JSONL
#   pr-review --run <url> [max_iterations]                      - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# URL-decode: + → space, %XX → byte
urldecode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

# Parse GitHub pulls URL into owner, repo, and search query
parse_pulls_url() {
  local url="$1"
  local base_url="${url%%\?*}"
  local query_string="${url#*\?}"

  # If no ?, query_string equals url
  if [ "$query_string" = "$url" ]; then
    query_string=""
  fi

  if [[ "$base_url" =~ github\.com/([^/]+)/([^/]+)/pulls$ ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
  else
    echo "Error: Invalid GitHub pulls URL: $url"
    echo ""
    echo "Expected format:"
    echo "  https://github.com/<owner>/<repo>/pulls?q=<filter>"
    echo ""
    echo "Example:"
    echo "  pr-review 'https://github.com/FactbirdHQ/nest/pulls?q=is%3Aopen+is%3Apr+user-review-requested%3A%40me+-is%3Adraft+-review%3Aapproved'"
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
  STATE_NAME="pr-review-${REPO_OWNER}-${REPO_NAME}-${query_hash}"
}

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  URL="${2:-}"
  if [ -z "$URL" ]; then
    echo "Usage: pr-review --follow <url> [--raw]"
    exit 1
  fi
  parse_pulls_url "$URL"
  exec claude-follow "$REPO/.state/$STATE_NAME" "${3:-}"
fi

# Run the loop directly (used internally by WezTerm spawn)
if [ "${1:-}" = "--run" ]; then
  shift
  URL="$1"
  shift
  MAX_ITERATIONS=${1:-10}

  parse_pulls_url "$URL"

  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

  mkdir -p "$STATE_DIR"

  grep -sq ".state/$STATE_NAME" "$REPO/.gitignore" || echo ".state/$STATE_NAME/" >> "$REPO/.gitignore"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - PR Review: $REPO_OWNER/$REPO_NAME" > "$PROGRESS_FILE"
    echo "Search: $SEARCH_QUERY" >> "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  echo "=== PR Review loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting PR Review Loop"
  echo "Repo: $REPO_OWNER/$REPO_NAME"
  echo "Search: $SEARCH_QUERY"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  AGENT_TEMPLATE=$(cat "$HOME/.claude/agents/pr-review.md")
  AGENT_PROMPT="${AGENT_TEMPLATE//__REPO_OWNER__/$REPO_OWNER}"
  AGENT_PROMPT="${AGENT_PROMPT//__REPO_NAME__/$REPO_NAME}"
  AGENT_PROMPT="${AGENT_PROMPT//__SEARCH_QUERY__/$SEARCH_QUERY}"
  AGENT_PROMPT="${AGENT_PROMPT//__STATE_NAME__/$STATE_NAME}"

  AGENT_PROMPT="$AGENT_PROMPT

$(cat "$HOME/.claude/agents/project-sleep.md")"

  SESSION_LOG="$STATE_DIR/session.log"

  SLEEP_COUNT=0

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
      echo "All PRs reviewed!"
      echo ""
      echo "Press Enter to close this tab..."
      read -r
      exit 0
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
  echo "Press Enter to close this tab..."
  read -r
  exit 1
fi

# Default: parse args and spawn in a new WezTerm window
URL="${1:-}"

if [ -z "$URL" ]; then
  echo "Usage: pr-review <url> [max_iterations]"
  echo ""
  echo "Arguments:"
  echo "  url             GitHub pulls URL with query filter"
  echo "  max_iterations  Maximum loop iterations (default: 10)"
  echo ""
  echo "Examples:"
  echo "  pr-review 'https://github.com/FactbirdHQ/nest/pulls?q=is%3Aopen+is%3Apr+user-review-requested%3A%40me+-is%3Adraft+-review%3Aapproved'"
  echo "  pr-review 'https://github.com/FactbirdHQ/nest/pulls?q=is%3Aopen+is%3Apr' 20"
  echo "  pr-review --follow 'https://github.com/FactbirdHQ/nest/pulls?q=...'"
  exit 1
fi

parse_pulls_url "$URL"
MAX_ITERATIONS=${2:-10}

STATE_DIR="$REPO/.state/$STATE_NAME"
LOG_FILE="$STATE_DIR/loop.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "Spawning PR Review loop in new WezTerm window..."
echo "Repo: $REPO_OWNER/$REPO_NAME"
echo "Search: $SEARCH_QUERY"

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$URL" "$MAX_ITERATIONS")
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --follow "$URL")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
