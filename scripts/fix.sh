# Usage: fix <pr> [max_iterations]
#   fix 123              - spawn WezTerm with CI fix loop for PR #123
#   fix https://github.com/Org/Repo/pull/123  - same, from a URL
#   fix 123 20           - same but with 20 max iterations
#   fix --follow <pr> [--raw] - follow Claude session JSONL across iterations
#   fix --run ...        - run the loop directly (used internally)
set -e

REPO="$(git rev-parse --show-toplevel)"

# Extract PR number from a GitHub URL or pass through a plain number
parse_pr() {
  local input="$1"
  if [[ "$input" =~ github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    PR_NUMBER="${BASH_REMATCH[3]}"
    PR_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$input" =~ ^[0-9]+$ ]]; then
    PR_NUMBER="$input"
    PR_REPO=""
  else
    echo "Error: Invalid PR reference: $input"
    echo "Expected a PR number or a GitHub pull request URL"
    exit 1
  fi
}

# Follow Claude session JSONL across iterations
if [ "${1:-}" = "--follow" ]; then
  if [ -z "${2:-}" ]; then
    echo "Usage: fix --follow <state_dir> [--raw]"
    exit 1
  fi
  exec claude-follow "$2" "${3:-}"
fi

# Run the loop directly (used internally by WezTerm spawn)
if [ "${1:-}" = "--run" ]; then
  shift
  parse_pr "$1"
  MAX_ITERATIONS=${2:-10}
  STATE_NAME="fix-$PR_NUMBER"
  STATE_DIR="$REPO/.state/$STATE_NAME"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LOG_FILE="$STATE_DIR/loop.log"

  CLAUDE_PROJECT_DIR="$HOME/.claude/projects/${REPO//[\/.]/\-}"

  mkdir -p "$STATE_DIR"

  grep -sq ".state/$STATE_NAME" "$REPO/.gitignore" || echo ".state/$STATE_NAME/" >> "$REPO/.gitignore"

  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Progress Log - Fix PR #$PR_NUMBER" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  echo "=== Fix loop started: $(date) ===" > "$LOG_FILE"

  echo "Starting CI Fix - PR #$PR_NUMBER"
  echo "Max iterations: $MAX_ITERATIONS"
  echo "Log file: $LOG_FILE"
  echo ""

  AGENT_PROMPT=$(sed -e "s/__PR__/$PR_NUMBER/g" -e "s|__REPO__|$PR_REPO|g" "$HOME/.claude/agents/fix.md")

  AGENT_PROMPT="$AGENT_PROMPT

$(cat "$HOME/.claude/agents/project-sleep.md")"

  SLEEP_COUNT=0

  for i in $(seq 1 $MAX_ITERATIONS); do
    echo "═══ Iteration $i ═══"

    SESSION_ID=$(uuidgen)
    SESSION_FILE="$CLAUDE_PROJECT_DIR/$SESSION_ID.jsonl"
    echo "$SESSION_FILE" > "$STATE_DIR/current_session"
    echo "Session: $SESSION_ID" >> "$LOG_FILE"

    OUTPUT=$(echo "$AGENT_PROMPT" | claude --session-id "$SESSION_ID" 2>&1 | tee -a "$LOG_FILE" /dev/stderr) || true

    if echo "$OUTPUT" | \
        grep -q "<promise>COMPLETE</promise>"
    then
      echo "✅ All CI checks passing for PR #$PR_NUMBER!"
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

# Validate arguments
if [ -z "${1:-}" ]; then
  echo "Usage: fix <pr> [max_iterations]"
  echo ""
  echo "Arguments:"
  echo "  pr              PR number or GitHub pull request URL"
  echo "  max_iterations  Maximum loop iterations (default: 10)"
  echo ""
  echo "Examples:"
  echo "  fix 123"
  echo "  fix https://github.com/Org/Repo/pull/123"
  echo "  fix 123 20"
  exit 1
fi

PR_INPUT="$1"
parse_pr "$PR_INPUT"
MAX_ITERATIONS=${2:-10}

# Verify the PR exists
REPO_FLAG=""
if [ -n "$PR_REPO" ]; then
  REPO_FLAG="--repo $PR_REPO"
fi
if ! gh pr view "$PR_NUMBER" $REPO_FLAG --json number >/dev/null 2>&1; then
  echo "Error: PR #$PR_NUMBER not found or not accessible"
  exit 1
fi

# Default: spawn in a new WezTerm window
STATE_NAME="fix-$PR_NUMBER"
STATE_DIR="$REPO/.state/$STATE_NAME"
LOG_FILE="$STATE_DIR/loop.log"

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"

echo "Spawning CI fix loop for PR #$PR_NUMBER in new WezTerm window..."

wezterm-ensure

LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$REPO" -- "$0" --run "$PR_INPUT" "$MAX_ITERATIONS")
sleep 1

SESSION_PANE_ID=$(wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$REPO" -- "$0" --follow "$STATE_DIR")

echo ""
echo "Loop started in pane: $LOOP_PANE_ID"
echo "Session started in pane: $SESSION_PANE_ID"
echo "Log file: $LOG_FILE"
