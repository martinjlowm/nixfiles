# Agent instructions

## Workflow

1. Read `./.state/__STATE_NAME__/progress.txt` for previously handled issues and learnings
2. Fetch issues matching the filter:
   ```
   gh issue list --repo __REPO_OWNER__/__REPO_NAME__ --search "__SEARCH_QUERY__" --json number,title,assignees,labels,state,url --limit 100
   ```
3. Get the current user:
   ```
   gh api user --jq '.login'
   ```
4. Filter to issues that are:
   - Still open
   - Not already handled, per progress.txt
5. Review PR feedback for all issues, even ones previously completed:
   - For each issue that already has a PR: `gh pr list --repo __REPO_OWNER__/__REPO_NAME__ --search "head:issues/" --state open --json number,title,headRefName,statusCheckRollup,mergeable`
   - Fetch comments via `gh pr view <pr> --repo __REPO_OWNER__/__REPO_NAME__ --comments` and `gh api repos/__REPO_OWNER__/__REPO_NAME__/pulls/{number}/comments`
   - Address **every** unresolved comment. Merge `origin/master` if needed. Skip if the PR is closed
   - Fix failing CI checks (see "Cancelled workflows"; warnings aren't failures)
   - Check CI for all PRs. If any required check has failed or been cancelled, investigate and fix
   - Check for merge conflicts on every PR, even passing ones: `gh pr view <pr> --repo __REPO_OWNER__/__REPO_NAME__ --json mergeable`. If `CONFLICTING`, resolve the conflicts by merging `origin/master`
   - If CI is still `PENDING`, skip and move on
6. Pick the next eligible issue, oldest first. Read full details:
   ```
   gh issue view <number> --repo __REPO_OWNER__/__REPO_NAME__
   ```
7. Assign yourself to the issue to signal it has been picked up:
   ```
   gh issue edit <number> --repo __REPO_OWNER__/__REPO_NAME__ --add-assignee @me
   ```
8. Set up working branch `issues/<issue-number>-<slug>`.
   - Bare repo (`git rev-parse --is-bare-repository` returns `true`): run `worktree <name>`. This is the `worktree` command in PATH, NOT `git worktree` and NOT the `EnterWorktree` tool
   - Regular repo: `git checkout -b <name> origin/master`
9. Enter the Nix dev shell before any work. It generates the pre-commit hooks
10. Implement the issue. Verify **every** acceptance criterion in the issue body before moving on. Run typecheck and tests for affected projects
11. Commit as `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - The body must include `Closes __REPO_OWNER__/__REPO_NAME__#<issue-number>`
    - Component is the specific project, or `*` for many
12. Push. NEVER force push, merge upstream first. Create the PR **always as draft** (`gh pr create --draft`), respecting the PR limit. **Never change a PR's draft/ready status.** Leave a draft as draft and a ready PR as ready. Re-evaluate the title and description against what was actually implemented
13. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 PR = 1 issue = 1 task.** Each issue gets exactly one PR. After completing steps 1 through 13 for one issue, **end the task**.

**NEVER wait or poll for CI.** Check CI status once. If checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Cancelled workflows

When most or all jobs show as `cancelled`, one job exited non-zero and the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators), never the root cause.

1. Identify the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. Find out why it failed. Grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```

Fix only the identified failure. Cancelled jobs and gates pass once it is resolved.

**Never blindly re-trigger CI.** A cancelled workflow always has a reason. Do not merge master and push just to re-trigger. Investigate first using the steps above.

Timeouts are the exception. If a job timed out (`timed_out` conclusion), retry with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure problems, not code failures.

## PR limit

Max **2 open PRs per search**. Check with `gh pr list --repo __REPO_OWNER__/__REPO_NAME__ --state open --author @me --search "head:issues/" | wc -l`

At 2 or more: push the branch but don't create a PR. Track it in `./.state/__STATE_NAME__/deferred-prs.json`:
```json
{"deferred": [{"branch": "issues/42-fix-login", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge or close.

## PR review tracking

Address every comment, either by implementing it or explaining the disagreement. Track in `./.state/__STATE_NAME__/review-state.json`:
```json
{"pr_number": 123, "last_addressed_comment_id": "IC_abc", "last_addressed_at": "<ISO>", "addressed_comments": [], "pending_comments": []}
```
Re-fetch after pushing. New comments may have arrived.

## Progress format

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

## Stop condition

When all matching issues have been processed, with a PR created or skipped with a reason: <promise>COMPLETE</promise>

If there are no matching issues at all: <promise>COMPLETE</promise>
