# claude-sleep: exponential backoff sleep for Claude loop scripts
#
# Usage: claude-sleep <count>
#   count - consecutive SLEEP count (0-based, incremented internally)
#
# Prints the new count to stdout. Logs to stderr.
# Backoff: 2 * 2^count minutes, capped at 60 minutes.

COUNT=$(($1 + 1))
BACKOFF=$((2 * (1 << (COUNT - 1))))
if [ $BACKOFF -gt 60 ]; then BACKOFF=60; fi

echo "💤 Blocked on CI/reviews. Sleeping $BACKOFF minutes (attempt $COUNT)..." >&2
sleep $((BACKOFF * 60))
echo "Resuming after sleep." >&2

echo "$COUNT"
