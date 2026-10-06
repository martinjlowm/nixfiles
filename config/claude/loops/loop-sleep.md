## Sleep

When nothing in this loop's workflow is actionable now and progress waits only on something
outside it (checks still running, a review not yet given, a PR in the merge queue), end the
iteration with `<promise>SLEEP</promise>` instead of polling. The loop then backs off, longer
each consecutive time, before the next iteration. Emit `SLEEP` and `COMPLETE` only as the
final line, never in passing.
