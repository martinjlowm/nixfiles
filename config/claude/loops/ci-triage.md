## CI triage

When most jobs in a run show `cancelled`, one job exited non-zero and the rest are its
cascade. Checks named "Complete" are `needs:` aggregators, never the root cause.

1. Find the job that failed:
   `gh run view <run-id> --log | grep 'exit code' | grep -v 'Complete'`
2. Find its error:
   `gh run view <run-id> --log | grep '<job-name>' | cut -f3- | grep -B10 -i 'error\|failed\|exception'`
3. Fix that failure only. The cancelled jobs and gates pass once it does.

Never push or merge only to re-trigger CI. The exception is a job with conclusion
`timed_out`, which you rerun with `gh run rerun <run-id> --failed`.
