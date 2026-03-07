# Agent Instructions

## Workflow

1. List all open Dependabot PRs:
   ```
   gh pr list --author "app/dependabot" --state open --json number,title,headRefName,mergeable,statusCheckRollup
   ```
2. Read `./.state/dependabot/progress.txt` for previously handled PRs and learnings
3. **Review PR feedback for all PRs** (even previously handled ones):
   - Fetch comments via `gh pr view <number> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment; rebase on `origin/master` if needed; skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for all PRs** — if any required check has failed or been cancelled, investigate before proceeding
   - **Check for merge conflicts on every PR**: `gh pr view <number> --json mergeable` — if `CONFLICTING`, comment `@dependabot rebase` on the PR, skip, and move on; if `UNKNOWN`, skip (GitHub is still computing). All PRs target `master` directly — no stacked PRs
4. For each open PR (oldest first), perform the following:

### Per-PR Steps

1. **Check CI status**: `gh pr checks <number> --json name,state,conclusion`
   - If any check state is `PENDING`, skip this PR and move to the next
   - If checks have failed, investigate (see **Troubleshooting Cancelled Workflows** below)
2. **Review the diff**: `gh pr diff <number>`
   - Verify the change is a straightforward dependency bump (version change in lockfile / manifest)
   - If the change looks suspicious or contains non-dependency changes, skip and note in progress
3. **Approve and merge**:
   ```
   gh pr review <number> --approve --body "Dependency update looks good. CI passes."
   gh pr merge <number> --squash --auto
   ```
4. **Log the result** in `./.state/dependabot/progress.txt`

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on. Waiting longer than 1 minute for CI results means you must stop immediately.

### Troubleshooting Cancelled Workflows

When most/all jobs show as `cancelled`, one job has a non-zero exit code — the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators) — never the root cause.

1. **Identify** the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. **Investigate** why it failed — grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```
3. If the failure is **transient** (timeout, flaky test, infrastructure): comment `@dependabot rebase` to retrigger
4. If the failure is a **real incompatibility**: skip the PR, note in progress.txt why it can't be auto-merged
5. **Never** push commits to a Dependabot branch — use `@dependabot rebase` or `@dependabot recreate` instead

Fix only the identified failure; cancelled jobs and gates will pass once resolved.

**Never blindly re-trigger CI.** If a workflow was cancelled, there is always a reason. Investigate why it was cancelled first using the steps above.

**Exception — timeouts:** If a job timed out (`timed_out` conclusion), comment `@dependabot rebase` to retrigger. Timeouts are transient infrastructure issues, not code failures.

## Progress Format

Append to `./.state/dependabot/progress.txt`:
```
## [Date] - PR #[number]
- Title: [PR title]
- Action: [merged|skipped|rebased|failed]
- Reason: [why, if skipped or failed]
---
```

## Stop Condition

When all open Dependabot PRs have been processed (merged, skipped with reason, or rebase-requested): <promise>COMPLETE</promise>

If there are no open Dependabot PRs at all: <promise>COMPLETE</promise>
