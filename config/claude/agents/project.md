# Agent Instructions

## Workflow

### Phase 1: Build or refresh the PRD

1. Read `./.state/__STATE_NAME__/progress.txt` for previously handled issues and learnings
2. If `__SPEC_FILE__` is not `NONE`, read the spec file at `__SPEC_FILE__` for additional technical context
3. Check if `./.state/__STATE_NAME__/prd.json` exists and read it
4. Fetch project items:
   ```
   gh project item-list __PROJECT_NUMBER__ --owner __PROJECT_OWNER__ --format json --limit 100
   ```
5. Get current user:
   ```
   gh api user --jq '.login'
   ```
6. Filter to items where:
   - `type` is `ISSUE`
   - `status` is NOT `Done` (or equivalent closed state)
   - Include ALL issues from incomplete sprints regardless of assignee — the PRD is a complete picture of remaining work. Only issues the agent can pick up (unassigned or assigned to current user) are eligible for Phase 3
7. **Create or update** `./.state/__STATE_NAME__/prd.json` with ALL issues from all incomplete sprints, grouped by sprint:
   ```json
   {
     "project": "__PROJECT_OWNER__/__PROJECT_NUMBER__",
     "created_at": "<ISO>",
     "updated_at": "<ISO>",
     "sprints": [
       {
         "name": "Sprint 3",
         "issues": [
           {
             "number": 123,
             "repo": "owner/repo",
             "title": "Issue title",
             "url": "https://github.com/owner/repo/issues/123",
             "assignees": [],
             "status": "pending",
             "pr_number": null,
             "pr_url": null,
             "skipped_reason": null
           }
         ]
       }
     ]
   }
   ```
   - Extract the sprint/iteration field from each project item (`gh project item-list` includes iteration fields). Issues without a sprint go into a `"name": "Backlog"` entry sorted last
   - **Include all incomplete sprints** — a sprint is incomplete if it has any issue not marked `Done` on the project board. Pull every issue from each incomplete sprint into the PRD
   - **Sprint ordering:** lowest sprint number first (highest priority)
   - `status` is one of: `pending`, `in-progress`, `pr-created`, `revised`, `skipped`
   - When updating an existing PRD: add new issues, remove issues that are now `Done` on the project board, drop sprints where all issues are resolved, preserve status of issues already tracked
   - Read full details of each issue (`gh issue view`) to populate the PRD

### Phase 2: Review existing PRs

8. **Review PR feedback for all issues** (even ones previously completed):
   - For each issue that already has a PR: `gh pr list --search "head:project-__PROJECT_NUMBER__/" --state open --json number,title,headRefName,body,statusCheckRollup,mergeable`
   - **Verify issue linkage:** ensure the PR body contains `Closes <issue-url>`. If missing, edit the PR body to add it (`gh pr edit <pr> --body ...`). This is required for the issue to auto-close and link to the project board
   - Fetch comments via `gh pr view <pr> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment including nits; rebase on base-branch (or origin/master if merged); skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for all PRs** — if any required check has failed or been cancelled, investigate and fix
   - **Check for merge conflicts on every PR** (even passing ones): `gh pr view <pr> --json mergeable` — if `CONFLICTING`, resolve the conflicts by rebasing on the base branch
   - If CI is still `PENDING`, skip and move on
   - Update the issue's status in `prd.json` to `revised` if changes were made

### Phase 3: Pick and implement ONE issue

9. From `prd.json`, pick the next issue with `status: "pending"` AND `assignees` empty or containing the current user, from the **first sprint** in the list (lowest sprint number = highest priority). Skip issues assigned to others. If no eligible issues remain in any sprint, go to the Stop Condition. Read full details:
   ```
   gh issue view <number> --repo <owner>/<repo>
   ```
10. Update the issue's status in `prd.json` to `in-progress`
11. **Assign yourself** to the issue to signal it has been picked up:
    ```
    gh issue edit <number> --repo <owner>/<repo> --add-assignee @me
    ```
12. Set up worktree: branch `project-__PROJECT_NUMBER__/<issue-number>-<slug>` off `origin/master`. Run: `worktree <name> --base origin/master`
13. Enter Nix dev shell before any work (generates pre-commit hooks)
14. Implement the issue. Verify **every** acceptance criterion mentioned in the issue body before moving on. Run typecheck and tests for affected projects
15. Commit: `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - Body must include: `Closes <issue-url>` (this auto-links to the project)
    - Component: specific project or `*` for many
16. Push (NEVER force push — merge upstream first). Create draft PR referencing the issue. Re-evaluate PR title and description to reflect what was actually implemented
17. Update `prd.json`: set the issue's status to `pr-created`, fill in `pr_number` and `pr_url`
18. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 PR = 1 Issue = 1 iteration.** Each issue gets exactly one PR. After completing steps 9–18 for one issue, **end the task** so the next iteration can begin.

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

Output `<promise>COMPLETE</promise>` when **either**:

1. Every issue across all sprints in `prd.json` has a status other than `pending` or `in-progress` (i.e., all are `pr-created`, `revised`, or `skipped`), OR
2. The PRD has zero sprints / zero issues, OR
3. The GitHub project has no unclaimed, incomplete issues (re-check via `gh project item-list` — if all remaining items are `Done` or assigned to someone else, the project is complete)

Otherwise, after handling one issue, simply end the task **without** outputting `<promise>COMPLETE</promise>`. The outer loop will start the next iteration.
