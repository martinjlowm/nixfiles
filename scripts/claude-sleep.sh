# claude-sleep: exponential backoff sleep for Claude loop scripts
#
# Usage: claude-sleep <count>
#   count - consecutive SLEEP count (0-based, incremented internally)
#
# Prints the new count to stdout. Logs to stderr.
# Backoff: Fibonacci sequence in minutes (1,1,2,3,5,8,13,21,34,55,...), capped at 60 minutes.

COUNT=$(($1 + 1))

# Compute Fibonacci(COUNT) starting at 2,2: 2,2,4,6,10,16,26,42,...
A=2; B=2
for i in $(seq 2 $COUNT); do
  TMP=$((A + B)); A=$B; B=$TMP
done
BACKOFF=$A
if [ $BACKOFF -gt 60 ]; then BACKOFF=60; fi

TOTAL=$((BACKOFF * 60))
FRAMES=("🌑" "🌒" "🌓" "🌔" "🌕" "🌖" "🌗" "🌘")
REMAINING=$TOTAL

while [ $REMAINING -gt 0 ]; do
  FRAME_IDX=$(( (TOTAL - REMAINING) % ${#FRAMES[@]} ))
  MINS=$((REMAINING / 60))
  SECS=$((REMAINING % 60))
  printf "\r${FRAMES[$FRAME_IDX]} Sleeping %02d:%02d  (attempt $COUNT, backoff ${BACKOFF}m) [Enter to skip]" "$MINS" "$SECS" >&2
  if read -r -t 1 2>/dev/null; then
    printf "\r⏩ Sleep skipped by user.%*s\n" 40 "" >&2
    echo "0"
    exit 0
  fi
  REMAINING=$((REMAINING - 1))
done

printf "\r✅ Resuming after ${BACKOFF}m sleep.%*s\n" 20 "" >&2

echo "$COUNT"
