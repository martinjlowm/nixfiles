# Agent Instructions

## Workflow

1. Read `./.state/__STATE_NAME__/progress.txt` for previously handled issues and learnings
2. Fetch issues matching the filter:
   ```
   gh issue list --repo __REPO_OWNER__/__REPO_NAME__ --search "__SEARCH_QUERY__" --json number,title,assignees,labels,state,url --limit 100
   ```
3. Get current user:
   ```
   gh api user --jq '.login'
   ```
4. Filter to issues that are:
   - Still open
   - Not already handled (check progress.txt)
5. **Review PR feedback for all issues** (even ones previously completed):
   - For each issue that already has a PR: `gh pr list --repo __REPO_OWNER__/__REPO_NAME__ --search "head:issues/" --state open --json number,title,headRefName,statusCheckRollup,mergeable`
   - Fetch comments via `gh pr view <pr> --repo __REPO_OWNER__/__REPO_NAME__ --comments` and `gh api repos/__REPO_OWNER__/__REPO_NAME__/pulls/{number}/comments`
   - Address **every** unresolved comment; rebase on `origin/master` if needed; skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for all PRs** — if any required check has failed or been cancelled, investigate and fix
   - **Check for merge conflicts on every PR** (even passing ones): `gh pr view <pr> --repo __REPO_OWNER__/__REPO_NAME__ --json mergeable` — if `CONFLICTING`, resolve the conflicts by rebasing on `origin/master`
   - If CI is still `PENDING`, skip and move on
6. Pick the next eligible issue (oldest first). Read full details:
   ```
   gh issue view <number> --repo __REPO_OWNER__/__REPO_NAME__
   ```
7. **Assign yourself** to the issue to signal it has been picked up:
   ```
   gh issue edit <number> --repo __REPO_OWNER__/__REPO_NAME__ --add-assignee @me
   ```
8. Set up worktree: branch `issues/<issue-number>-<slug>` off `origin/master`. Run: `worktree <name> --base origin/master`
9. Enter Nix dev shell before any work (generates pre-commit hooks)
10. Implement the issue. Verify **every** acceptance criterion mentioned in the issue body before moving on. Run typecheck and tests for affected projects
11. Commit: `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - Body must include: `Closes __REPO_OWNER__/__REPO_NAME__#<issue-number>`
    - Component: specific project or `*` for many
12. Push (NEVER force push — merge upstream first). Create draft PR referencing the issue. Re-evaluate PR title and description to reflect what was actually implemented
13. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 PR = 1 Issue = 1 Task.** Each issue gets exactly one PR. After completing steps 1–13 for one issue, **end the task**.

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Troubleshooting Cancelled Workflows

When most/all jobs show as `cancelled`, one job has a non-zero exit code — the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators) — never the root cause.

1. **Identify** the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. **Investigate** why it failed — grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```

Fix only the identified failure; cancelled jobs and gates will pass once resolved.

**Never blindly re-trigger CI.** If a workflow was cancelled, there is always a reason. Do not merge master and push just to re-trigger — investigate why it was cancelled first using the steps above.

**Exception — timeouts:** If a job timed out (`timed_out` conclusion), retry with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure issues, not code failures.

## PR Limit

Max **5 open PRs per search**. Check: `gh pr list --repo __REPO_OWNER__/__REPO_NAME__ --state open --author @me --search "head:issues/" | wc -l`

If ≥5: push branch but don't create PR. Track in `./.state/__STATE_NAME__/deferred-prs.json`:
```json
{"deferred": [{"branch": "issues/42-fix-login", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge/close.

## PR Review Tracking

Address every comment (implement or explain disagreement). Track in `./.state/__STATE_NAME__/review-state.json`:
```json
{"pr_number": 123, "last_addressed_comment_id": "IC_abc", "last_addressed_at": "<ISO>", "addressed_comments": [], "pending_comments": []}
```
Re-fetch after push — new comments may arrive.

## Progress Format

Append to `./.state/__STATE_NAME__/progress.txt`:
```
## [Date] - Issue #[number]
- Title: [Issue title]
- What was implemented
- Files changed
- Action: [pr-created|revised|skipped]
- Learnings: patterns, gotchas
---
```

**progress.txt is strictly for implementation notes and learnings.** Do NOT write:
- CI status, check results, or pass/fail state
- Batch status listings across multiple issues
- "Next iteration" action items or plans

Add reusable **Codebase Patterns** to the TOP of progress.txt.

## Stop Condition

When all matching issues have been processed (PR created, or skipped with reason): <promise>COMPLETE</promise>

If there are no matching issues at all: <promise>COMPLETE</promise>
