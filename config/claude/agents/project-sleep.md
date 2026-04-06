# Sleep Condition (for project agent)

Apply this to `project.md` Stop Condition section and `project.sh` when backoff behavior is needed.

## Agent instructions addition

Add to the Stop Condition section in `project.md`:

### Sleep Condition

Output `<promise>SLEEP</promise>` when **all** of the following are true:

1. No issues with `status: "pending"` are eligible to pick up (all remaining are assigned to others, or all are already `pr-created`/`revised`/`skipped`)
2. Forward progress is blocked by one or more of:
   - CI is still running on open PRs
   - PRs are awaiting review (no new review comments to address)
   - PRs are in the merge queue
3. There is nothing actionable to do right now

`<promise>SLEEP</promise>` pauses the outer loop for 15 minutes before the next iteration. Use this instead of polling — it lets the agent back off while waiting for external events (CI completion, reviewer feedback, merge queue processing).

Also update the final paragraph to:
> Otherwise, after handling one issue, simply end the task **without** outputting `<promise>COMPLETE</promise>` or `<promise>SLEEP</promise>`. The outer loop will start the next iteration.

## Script addition

Add to `project.sh` inside the `--run` loop, after the COMPLETE check:

```bash
if echo "$OUTPUT" | \
    grep -q "<promise>SLEEP</promise>"
then
  echo "💤 Blocked on CI/reviews. Sleeping 15 minutes..."
  sleep 900
  echo "Resuming after sleep."
  continue
fi
```
