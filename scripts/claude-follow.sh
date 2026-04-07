# Usage: claude-follow <state-dir> [--raw]
#   claude-follow /path/to/.state/foo        - follow sessions with jq formatting
#   claude-follow /path/to/.state/foo --raw  - follow raw JSONL
set -e

STATE_DIR="${1:-}"
RAW=false

if [ -z "$STATE_DIR" ]; then
  echo "Usage: claude-follow <state-dir> [--raw]"
  exit 1
fi

if [ "${2:-}" = "--raw" ]; then
  RAW=true
fi

CURRENT_SESSION_FILE="$STATE_DIR/current_session"

echo "Watching for Claude sessions in $STATE_DIR..."

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
      if [ "$RAW" = true ]; then
        tail -f "$ACTIVE_SESSION" &
      else
        tail -f "$ACTIVE_SESSION" | jq --unbuffered -r '
          select(.message) |
          .message.role as $role |
          (if .message.content | type == "string" then
            .message.content
          else
            (.message.content // [] | map(.text // "") | join(""))
          end) as $text |
          select($text | length > 0) |
          if $role == "user" then
            "\u001b[2m▸ user input\u001b[0m"
          else
            "\u001b[36m[\(.timestamp)]\u001b[0m \($text)"
          end
        ' &
      fi
      TAIL_PID=$!
    fi
  fi
  sleep 2
done
