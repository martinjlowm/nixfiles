## CI triage

If most jobs in a run show `cancelled`, one job exited non-zero and the rest are its cascade.
Checks named "Complete" are `needs:` aggregators, never the root cause.

1. Find the job that failed:
   `gh run view <run-id> --log | grep 'exit code' | grep -v 'Complete'`
2. Find its error:
   `gh run view <run-id> --log | grep '<job-name>' | cut -f3- | grep -B10 -i 'error\|failed\|exception'`
3. Fix that failure only. The cancelled jobs and gates pass once it does.

If a job's conclusion is `timed_out`, rerun it with `gh run rerun <run-id> --failed`.
Otherwise never push or merge only to re-trigger CI.
