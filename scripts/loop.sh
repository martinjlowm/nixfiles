# Usage: loop [max_iterations]
set -e

MAX_ITERATIONS=''${1:-10}
REPO="$(git rev-parse --show-toplevel)"
PROGRESS_FILE="$REPO/.state/progress.md"

grep -sq '.state/progress.txt' "$REPO/.gitignore" || echo ".state/progress.txt" >> "$REPO/.gitignore"
grep -sq '.state/prd.json' "$REPO/.gitignore" || echo ".state/prd.json" >> "$REPO/.gitignore"

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Loop - Max iterations: $MAX_ITERATIONS"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══ Iteration $i ═══"

  OUTPUT=$(cat "$HOME/.claude/agents/loop.md}" | claude -p --dangerously-skip-permissions 2>&1 | tee /dev/stderr) || true

  if echo "$OUTPUT" | \
      grep -q "<promise>COMPLETE</promise>"
  then
    echo "✅ Done!"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Loop reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
