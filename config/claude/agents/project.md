# Agent Instructions

## Workflow

1. Read `./.state/__STATE_NAME__/progress.txt` for previously handled issues and learnings
2. If `__SPEC_FILE__` is not `NONE`, read the spec file at `__SPEC_FILE__` for additional technical context
3. Fetch project items:
   ```
   gh project item-list __PROJECT_NUMBER__ --owner __PROJECT_OWNER__ --format json --limit 100
   ```
4. Get current user:
   ```
   gh api user --jq '.login'
   ```
5. Filter to items where:
   - `type` is `ISSUE`
   - `status` is NOT `Done` (or equivalent closed state)
   - `assignees` is empty (unassigned) OR contains the current user
6. **Review PR feedback for all issues** (even ones previously completed):
   - For each issue that already has a PR: `gh pr list --search "head:project-__PROJECT_NUMBER__/" --state open --json number,title,headRefName,statusCheckRollup,mergeable`
   - Fetch comments via `gh pr view <pr> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment; rebase on base-branch (or origin/master if merged); skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for all PRs** — if any required check has failed or been cancelled, investigate and fix
   - **Check for merge conflicts on every PR** (even passing ones): `gh pr view <pr> --json mergeable` — if `CONFLICTING`, resolve the conflicts by rebasing on the base branch
   - If CI is still `PENDING`, skip and move on
7. Pick the next eligible issue (oldest/highest priority first). Read full details:
   ```
   gh issue view <number> --repo <owner>/<repo>
   ```
8. **Assign yourself** to the issue to signal it has been picked up:
   ```
   gh issue edit <number> --repo <owner>/<repo> --add-assignee @me
   ```
9. Set up worktree: branch `project-__PROJECT_NUMBER__/<issue-number>-<slug>` off `origin/master`. Run: `worktree <name> --base origin/master`
10. Enter Nix dev shell before any work (generates pre-commit hooks)
11. Implement the issue. Verify **every** acceptance criterion mentioned in the issue body before moving on. Run typecheck and tests for affected projects
12. Commit: `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - Body must include: `Closes <issue-url>` (this auto-links to the project)
    - Component: specific project or `*` for many
13. Push (NEVER force push — merge upstream first). Create draft PR referencing the issue. Re-evaluate PR title and description to reflect what was actually implemented
14. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 PR = 1 Issue = 1 Task.** Each issue gets exactly one PR. After completing steps 1–14 for one issue, **end the task**.

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

Max **5 open PRs per project**. Check: `gh pr list --state open --author @me --search "head:project-__PROJECT_NUMBER__/" | wc -l`

If ≥5: push branch but don't create PR. Track in `./.state/__STATE_NAME__/deferred-prs.json`:
```json
{"deferred": [{"branch": "project-__PROJECT_NUMBER__/42-fix-login", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
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

When all eligible issues have been processed (PR created, or skipped with reason): <promise>COMPLETE</promise>

If there are no eligible issues at all: <promise>COMPLETE</promise>
