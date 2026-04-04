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
12. **Record timing — issue picked up.** Write/update `./.state/__STATE_NAME__/timing/<issue-number>.json` (see **Timing Tracking** below) with `picked_up_at` set to the current UTC time
13. Set up worktree by running: `worktree project-__PROJECT_NUMBER__/<issue-number>-<slug>` — this is the `worktree` command in PATH, NOT `git worktree` and NOT the `EnterWorktree` tool. Then `cd` into the created worktree directory
14. Enter Nix dev shell before any work (generates pre-commit hooks)
15. Implement the issue. Verify **every** acceptance criterion mentioned in the issue body before moving on. Run typecheck and tests for affected projects
16. Commit: `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - Body must include: `Closes <issue-url>` (this auto-links to the project)
    - Component: specific project or `*` for many
17. Push (NEVER force push — merge upstream first). Create draft PR referencing the issue. Re-evaluate PR title and description to reflect what was actually implemented
18. **Record timing — pushed for review.** Update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `pushed_for_review_at` set to the current UTC time
19. Update `prd.json`: set the issue's status to `pr-created`, fill in `pr_number` and `pr_url`
20. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 PR = 1 Issue = 1 iteration.** Each issue gets exactly one PR. After completing steps 9–20 for one issue, **end the task** so the next iteration can begin.

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

### Phase 4: Detect merge queue and closure

During Phase 2 (PR review), also check for PRs that have entered the merge queue or have been merged:

21. For each issue with `status: "pr-created"` or `"revised"` in `prd.json`, check its PR:
    ```
    gh pr view <pr_number> --json mergeQueueEntry,mergedAt,state,closedAt
    ```
22. **Merge queue detected:** If `mergeQueueEntry` is non-null and `merged_queue_entered_at` is not yet recorded, update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `merge_queue_entered_at` set to the current UTC time
23. **PR merged / issue closed:** If `state` is `MERGED`:
    - Update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `merged_at` set to the `mergedAt` value from the PR (already in ISO8601 UTC)
    - Check the linked issue: `gh issue view <number> --repo <owner>/<repo> --json closedAt,state`
    - If the issue is closed, record `issue_closed_at` from the issue's `closedAt` field
    - **Post a project status update** (see **Project Status Update on Closure** below)
    - Remove the issue from `prd.json` (it is now `Done`)

## Timing Tracking

Store per-issue timing data in `./.state/__STATE_NAME__/timing/<issue-number>.json`. All timestamps are **UTC in ISO8601 format** (e.g. `2026-04-04T14:30:00Z`).

```json
{
  "issue_number": 123,
  "repo": "owner/repo",
  "title": "Issue title",
  "pr_number": 456,
  "picked_up_at": "2026-04-04T14:30:00Z",
  "pushed_for_review_at": "2026-04-04T15:45:00Z",
  "merge_queue_entered_at": "2026-04-04T16:00:00Z",
  "merged_at": "2026-04-04T16:05:00Z",
  "issue_closed_at": "2026-04-04T16:05:00Z"
}
```

Fields are filled incrementally as each event occurs. Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` to get the current UTC time when recording `picked_up_at`, `pushed_for_review_at`, and `merge_queue_entered_at`. For `merged_at` and `issue_closed_at`, use the values returned by the GitHub API.

## Project Status Update on Closure

When an issue is closed (step 23), post a status update to the GitHub project using the GraphQL API:

```bash
gh api graphql -f query='
mutation {
  createProjectV2StatusUpdate(
    input: {
      projectId: "__PROJECT_ID__",
      body: "Issue #<number> (<title>) closed. PR #<pr_number> merged.\n\nTimeline:\n- Picked up: <picked_up_at>\n- Pushed for review: <pushed_for_review_at>\n- Merge queue entered: <merge_queue_entered_at>\n- Merged: <merged_at>\n- Issue closed: <issue_closed_at>",
      startDate: "<picked_up_at date portion>",
      targetDate: "<issue_closed_at date portion>",
      status: ON_TRACK
    }
  ) {
    statusUpdate {
      id
    }
  }
}'
```

- `__PROJECT_ID__` is the **node ID** of the project (obtain via `gh project view __PROJECT_NUMBER__ --owner __PROJECT_OWNER__ --format json --jq '.id'` and cache in `./.state/__STATE_NAME__/project-id.txt`)
- `startDate` and `targetDate` use the date portion only (`YYYY-MM-DD`) from the timing record
- Populate the body with all timestamps from the timing file

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

**Stacked draft PR:** In addition to deferring, maintain a single **draft PR** (`project-__PROJECT_NUMBER__/stack`) that combines all deferred branches into one. This gives reviewers visibility into the full scope of upcoming work.

1. If the stack branch doesn't exist yet, create it off `origin/master`:
   ```
   git checkout -b project-__PROJECT_NUMBER__/stack origin/master
   ```
2. Merge each deferred branch into the stack branch (in order of issue priority):
   ```
   git merge --no-ff project-__PROJECT_NUMBER__/<issue-number>-<slug>
   ```
3. Push the stack branch and open (or update) a **draft** PR:
   ```
   gh pr create --draft --title "Stack: project-__PROJECT_NUMBER__ deferred PRs" \
     --body "$(cat <<'EOF'
   ## Stacked changes

   This draft PR combines the following deferred branches for visibility:

   - [ ] `project-__PROJECT_NUMBER__/<branch-1>` — #<issue> <title>
   - [ ] `project-__PROJECT_NUMBER__/<branch-2>` — #<issue> <title>

   **Do not merge this PR directly.** Individual PRs will be created from each branch when slots open up.
   EOF
   )"
   ```
   If the draft PR already exists, update its branch (`git push`) and edit the body to reflect the current set of deferred branches: `gh pr edit <stack-pr> --body ...`
4. Track the stack PR in `./.state/__STATE_NAME__/deferred-prs.json`:
   ```json
   {"stack_pr": {"number": 99, "branch": "project-__PROJECT_NUMBER__/stack"}, "deferred": [...]}
   ```
5. When a deferred branch gets its own PR (slot opened up), rebase the stack branch to drop that branch's commits and update the draft PR body. Close the stack PR when no deferred branches remain.

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

1. Every issue across all sprints in `prd.json` has a status other than `pending` or `in-progress` (i.e., all are `pr-created`, `revised`, or `skipped`) **AND no PRs are open or in the merge queue** (all work is fully merged or skipped), OR
2. The PRD has zero sprints / zero issues, OR
3. The GitHub project has no unclaimed, incomplete issues (re-check via `gh project item-list` — if all remaining items are `Done` or assigned to someone else, the project is complete)

**Do NOT emit `COMPLETE` if any PRs are still open, awaiting review, or in the merge queue.** The project is not done until all PRs have landed.

### Sleep Condition

Output `<promise>SLEEP</promise>` when **all** of the following are true:

1. No issues with `status: "pending"` are eligible to pick up (all remaining are assigned to others, or all are already `pr-created`/`revised`/`skipped`)
2. Forward progress is blocked by one or more of:
   - CI is still running on open PRs
   - PRs are awaiting review (no new review comments to address)
   - PRs are in the merge queue
3. There is nothing actionable to do right now

`<promise>SLEEP</promise>` pauses the outer loop for 15 minutes before the next iteration. Use this instead of polling — it lets the agent back off while waiting for external events (CI completion, reviewer feedback, merge queue processing).

Otherwise, after handling one issue, simply end the task **without** outputting `<promise>COMPLETE</promise>` or `<promise>SLEEP</promise>`. The outer loop will start the next iteration.
