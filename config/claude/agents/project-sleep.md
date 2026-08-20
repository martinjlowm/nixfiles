# Sleep condition (for the project agent)

Apply this to the stop condition section of `project.md` and to `project.sh` when you need backoff behavior.

## Agent instructions addition

Add to the stop condition section in `project.md`:

### Sleep condition

Output `<promise>SLEEP</promise>` when **all** of the following are true:

1. No issues with `status: "pending"` are eligible to pick up. All remaining ones are assigned to others, or already `pr-created`, `revised`, or `skipped`
2. Forward progress is blocked by at least one of:
   - CI still running on open PRs
   - PRs awaiting review, with no new review comments to address
   - PRs in the merge queue
3. Nothing is actionable right now

`<promise>SLEEP</promise>` pauses the outer loop for 15 minutes before the next iteration. Use it instead of polling. It lets the agent back off while waiting for external events: CI completion, reviewer feedback, merge queue processing.

Also update the final paragraph to:
> Otherwise, after handling one issue, end the task **without** outputting `<promise>COMPLETE</promise>` or `<promise>SLEEP</promise>`. The outer loop starts the next iteration.

## Script addition

Add to `project.sh` inside the `--run` loop, after the COMPLETE check:

```bash
if echo "$OUTPUT" | \
    grep -q "<promise>SLEEP</promise>"
then
  echo "Blocked on CI or reviews. Sleeping 15 minutes..."
  sleep 900
  echo "Resuming after sleep."
  continue
fi
```
