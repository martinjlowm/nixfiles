# Agent instructions

## Workflow

### Phase 1: build or refresh the PRD

1. Read `./.state/__STATE_NAME__/progress.txt` for previously handled issues and learnings
2. If `__SPEC_FILE__` is not `NONE`, read the spec file at `__SPEC_FILE__` for extra technical context
3. Check whether `./.state/__STATE_NAME__/prd.json` exists and read it
4. Fetch project items:
   ```
   gh project item-list __PROJECT_NUMBER__ --owner __PROJECT_OWNER__ --format json --limit 100
   ```
5. Get the current user:
   ```
   gh api user --jq '.login'
   ```
6. Filter to items where:
   - `type` is `ISSUE`
   - `status` is NOT `Done`, or an equivalent closed state
   - Include ALL issues from incomplete sprints regardless of assignee. The PRD is a complete picture of remaining work. Only issues the agent can pick up, unassigned or assigned to the current user, are eligible for Phase 3
7. Create or update `./.state/__STATE_NAME__/prd.json` with ALL issues from all incomplete sprints, grouped by sprint:
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
   - Extract the sprint or iteration field from each project item. `gh project item-list` includes iteration fields. Issues without a sprint go into a `"name": "Backlog"` entry sorted last
   - Include all incomplete sprints. A sprint is incomplete if any of its issues is not marked `Done` on the project board. Pull every issue from each incomplete sprint into the PRD
   - Sprint ordering: lowest sprint number first, which is highest priority
   - `status` is one of `pending`, `in-progress`, `pr-created`, `revised`, `skipped`
   - When updating an existing PRD, add new issues, remove issues that are now `Done` on the project board, drop sprints where all issues are resolved, and preserve the status of issues already tracked
   - Read full details of each issue (`gh issue view`) to populate the PRD

### Phase 2: review existing PRs

8. Review PR feedback for all issues, even ones previously completed, **and the stacked draft PR** if one exists:
   - For each issue that already has a PR, plus the stacked PR: `gh pr list --search "head:project-__PROJECT_NUMBER__/" --state open --json number,title,headRefName,baseRefName,body,statusCheckRollup,mergeable`
   - Verify issue linkage. The PR body must contain `Closes <issue-url>`. If it is missing, edit the PR body to add it (`gh pr edit <pr> --body ...`). The issue needs this to auto-close and link to the project board
   - Fetch comments via `gh pr view <pr> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment including nits. Merge base-branch, or origin/master if merged. Skip if the PR is closed
   - Fix failing CI checks (see "Cancelled workflows"; warnings aren't failures)
   - Check CI for all PRs. If any required check has failed or been cancelled, investigate and fix. **This includes stacked and chained PRs.** A failing check on a child PR may come from the parent, so always check the full chain
   - Check for merge conflicts on every PR, even passing ones: `gh pr view <pr> --json mergeable`. If `CONFLICTING`, resolve the conflicts by merging the base branch
   - If CI is still `PENDING`, skip and move on. **Ignore Chromatic checks.** They need manual approval and are not part of the automated CI gate
   - Review comments on stacked PRs. When PRs are chained, meaning a child PR targets a parent PR branch, review comments apply to the **entire chain**. A comment on a child PR may point out something the parent introduced. Address it where the code originates, then merge through the chain
   - Propagate changes across all project PRs. When resolving a PR comment that changes behavior also present in other PRs, such as a naming convention, API pattern, or shared logic, update every affected PR to match, both forward and backward. Check all open project PRs (`project-__PROJECT_NUMBER__/`) for the same pattern and apply the fix consistently
   - Backpropagate to earlier PRs. When reviewing a later PR reveals a problem that originated in an earlier or dependent PR, such as a pattern established in PR #1 that PR #3's reviewer flags, fix the root cause in the earlier PR first, then merge into the later PRs. That keeps the same review comment from appearing on every dependent PR
   - **Verify stack integrity (MANDATORY).** For every open project PR, verify the stacking order is correct and the stack is current with `master`:
     1. List all open PRs: `gh pr list --search "head:project-__PROJECT_NUMBER__/" --state open --json number,headRefName,baseRefName`
     2. Each PR's `baseRefName` must be the branch of the **previous PR in the chain**, ordered by issue priority from the PRD, except the first PR, which must target `master`
     3. If any PR targets `master` when it should target a parent branch, meaning it was created independently instead of stacked, **fix it immediately**: `gh pr edit <pr> --base project-__PROJECT_NUMBER__/<parent-branch>` and merge the parent branch into the child
     4. If any PR targets the wrong parent, out of order, retarget and merge to restore the correct chain
     5. Merge `master` into the stack when it is significantly stale. Fetch `origin/master` and check whether the root branch, the first PR in the chain, is behind. Only merge if the root branch is **more than one week behind** `origin/master`, that is, the oldest commit on `origin/master` not in the root branch is older than 7 days: `git log --format='%ci' --reverse <root-branch>..origin/master | head -1`. If that date is more than 7 days ago, merge. If within one week, skip this step. When merging, merge `origin/master` into the root branch, then merge each parent into its child in order. That avoids churn while keeping merge conflicts from accumulating
     6. **Do not proceed to Phase 3 until all PRs are correctly stacked**, with `master` merged in if more than a week behind. Unstacked or significantly stale PRs are what force impractical stack rebuilds and merge queue failures. Fixing the stacking order outranks implementing new issues
   - Update the issue's status in `prd.json` to `revised` if you made changes

### Phase 3: pick and implement ONE issue

9. From `prd.json`, pick the next issue with `status: "pending"` AND `assignees` either empty or containing the current user, from the **first sprint** in the list (lowest sprint number is highest priority). Skip issues assigned to others. If no eligible issues remain in any sprint, go to the stop condition. Read full details:
   ```
   gh issue view <number> --repo <owner>/<repo>
   ```
10. Update the issue's status in `prd.json` to `in-progress`
11. Assign yourself to the issue to signal it has been picked up:
    ```
    gh issue edit <number> --repo <owner>/<repo> --add-assignee @me
    ```
12. Record timing for the pickup. Write or update `./.state/__STATE_NAME__/timing/<issue-number>.json` (see "Timing tracking") with `picked_up_at` set to the current UTC time
13. Set up working branch `project-__PROJECT_NUMBER__/<issue-number>-<slug>`.
    - Bare repo (`git rev-parse --is-bare-repository` returns `true`): run `worktree project-__PROJECT_NUMBER__/<issue-number>-<slug>`. This is the `worktree` command in PATH, NOT `git worktree` and NOT the `EnterWorktree` tool. Then `cd` into the created worktree directory.
    - Regular repo: `git checkout -b project-__PROJECT_NUMBER__/<issue-number>-<slug> origin/master`
    Stack the branch. If other project branches exist, merge the tip of the most recent one: `git merge project-__PROJECT_NUMBER__/<previous-branch>`. That makes the new branch additive on top of all prior work
14. Enter the Nix dev shell before any work. It generates the pre-commit hooks
15. Implement the issue. Verify **every** acceptance criterion in the issue body before moving on. Run typecheck and tests for affected projects. If the issue touches UI code, run a visual comparison (see "Visual comparison for UI changes")
16. Commit as `[feat|fix|chore](<Component>): #<issue-number> - <Title>`
    - The body must include `Closes <issue-url>`, which auto-links to the project
    - Component is the specific project, or `*` for many
17. Push. NEVER force push, merge upstream first. Create the PR **always as draft** (`gh pr create --draft`), respecting the PR limit. **Never change a PR's draft/ready status.** Leave a draft as draft and a ready PR as ready. Re-evaluate the title and description against what was actually implemented. Use this PR body format:
    ```
    ## Summary
    <1-3 bullet points describing what was implemented>

    Closes <issue-url>

    ## Test plan
    - [ ] <concrete verification step, e.g. "Run `nix build .#package`, succeeds">
    - [ ] <another verification step>
    - [ ] CI passes (typecheck, tests, lint)
    ```
    Keep the test plan current. When revising a PR in Phase 2, update the checkboxes against the latest state: check off items that pass, add new items for changes made during revision, and note any blockers
18. Record timing for the push. Update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `pushed_for_review_at` set to the current UTC time
19. Verify the new PR is correctly stacked. After creating the PR, confirm:
    - The PR's base branch is the previous project branch, not `master`, unless this is the first PR in the chain
    - The branch actually contains the parent's commits. `git log --oneline project-__PROJECT_NUMBER__/<parent-branch>..HEAD` should show only this PR's commits
    - If either check fails, fix it before proceeding: `gh pr edit <pr> --base <correct-parent>` and merge the parent
20. Update `prd.json`: set the issue's status to `pr-created` and fill in `pr_number` and `pr_url`
21. Log the result in `./.state/__STATE_NAME__/progress.txt`

**1 issue = 1 branch, and 1 PR once created.** Every issue gets its own dedicated branch, always mapping 1:1. In a bare repo, each branch gets its own worktree. A PR is created from that branch when ready, or deferred if the PR limit is reached, but the branch exists regardless. Never share a branch across issues, and never create multiple branches for a single issue. After completing steps 9 through 21 for one issue, **end the task** so the next iteration can begin.

**Stacked (chained) PRs are the default.** Every new issue branch MUST be based on the **tip of the most recent project branch** (the last PR in the stack), not on `master`. That makes each PR additive. It contains only its own diff on top of the previous work. When the base PR merges, GitHub retargets the child to `master`.

- Use `git checkout -b project-__PROJECT_NUMBER__/<new-branch> project-__PROJECT_NUMBER__/<previous-branch>` when creating the branch
- Use `gh pr create --base project-__PROJECT_NUMBER__/<previous-branch>` when creating the PR
- Track the dependency in `prd.json` by adding `"depends_on_pr": <parent-pr-number>` to the issue entry
- **The only exception** is an issue completely unrelated to any existing project branch (different module, no shared files). Branching from `master` is acceptable then, but default to stacking

So the "stack" is just the latest branch in the chain, and no separate merge step is needed. With N stacked PRs, branch N already contains all changes from branches 1 through N-1.

**Stacked PR maintenance is mandatory:**
- Since every branch builds on the previous, the stack is additive and each PR's diff is only its own changes
- **The stack should not fall too far behind `master`.** Before any other stack maintenance, fetch `origin/master` and check whether the root branch is more than one week behind. If so, merge `origin/master` into the root branch, then cascade merges through each child in order (merge parent into child). A stale stack causes merge conflicts, CI failures in the merge queue, and wasted reviewer time, but merging on every minor upstream change creates churn
- When updating the stack, **always start from the root of the chain outward**. Merge into the root first, then merge each parent into its child in order. Never rebuild the whole stack from scratch. That is impractical at scale
- A fix in a parent PR **must** be followed by merging the parent into all children so they pick up the change
- Comments and CI failures on **any PR in the chain** must be addressed. Do not skip a child PR because "the parent will fix it later"
- When a reviewer comments on a child PR about code that originates in the parent, fix it in the parent and merge through the chain. The child PR's diff stays clean

**NEVER wait or poll for CI.** Check CI status once. If checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

### Phase 4: detect merge queue and closure

During Phase 2, PR review, also check for PRs that have entered the merge queue or been merged:

22. For each issue with `status: "pr-created"` or `"revised"` in `prd.json`, check its PR:
    ```
    gh pr view <pr_number> --json mergeQueueEntry,mergedAt,state,closedAt
    ```
23. Merge queue detected. If `mergeQueueEntry` is non-null and `merged_queue_entered_at` is not yet recorded, update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `merge_queue_entered_at` set to the current UTC time
24. Merge queue CI failure. If the PR was removed from the merge queue by a failed CI check, meaning `mergeQueueEntry` is null, `state` is `OPEN`, and the PR was previously recorded as entering the merge queue:
    - Check the merge queue run with `gh pr checks <pr_number>` and identify which check failed
    - These are integration-test failures. They happen when the PR is merged on top of the latest `master` plus other queued PRs. Local CI may have passed while the combined state fails. Treat them as high priority, since the PR was already approved and ready to land
    - Investigate using the "Cancelled workflows" steps. The failure usually comes from a conflict or incompatibility with another PR that merged while this one was queued
    - Fix it in the feature branch and push. The PR then needs to re-enter the merge queue
    - Update `prd.json`: set the issue's status back to `revised`
    - Clear `merge_queue_entered_at` from the timing file so it can be re-recorded on the next queue entry
25. PR merged and issue closed. If `state` is `MERGED`:
    - Update `./.state/__STATE_NAME__/timing/<issue-number>.json` with `merged_at` set to the PR's `mergedAt` value, already ISO8601 UTC
    - Check the linked issue: `gh issue view <number> --repo <owner>/<repo> --json closedAt,state`
    - If the issue is closed, record `issue_closed_at` from the issue's `closedAt` field
    - Post a project status update (see "Project status update on closure")
    - Remove the issue from `prd.json`. It is now `Done`

## Timing tracking

Store per-issue timing data in `./.state/__STATE_NAME__/timing/<issue-number>.json`. All timestamps are **UTC in ISO8601 format**, for example `2026-04-04T14:30:00Z`.

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

Fill fields incrementally as each event happens. Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` for the current UTC time when recording `picked_up_at`, `pushed_for_review_at`, and `merge_queue_entered_at`. For `merged_at` and `issue_closed_at`, use the values the GitHub API returns.

## Project status update on closure

When an issue closes (step 25), post a status update to the GitHub project using the GraphQL API:

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

- `__PROJECT_ID__` is the **node ID** of the project. Get it via `gh project view __PROJECT_NUMBER__ --owner __PROJECT_OWNER__ --format json --jq '.id'` and cache it in `./.state/__STATE_NAME__/project-id.txt`
- `startDate` and `targetDate` take the date portion only (`YYYY-MM-DD`) from the timing record
- Populate the body with all timestamps from the timing file

## Visual comparison for UI changes

When an issue modifies UI code (components, styles, layouts, pages, any file that affects what users see in the browser), run the `visual-comparison` skill to check that no Mixpanel-tracked components or other critical UI paths have regressed.

### When to trigger

A visual comparison is required when the issue's changes touch:
- React/Vue/Svelte/Angular components (`.tsx`, `.jsx`, `.vue`, `.svelte`)
- Stylesheets or CSS-in-JS (`.css`, `.scss`, `.less`, `styled-components`, `tailwind` class changes)
- Layout or routing files (`pages/`, `app/`, router configs)
- Shared UI utilities (design system tokens, theme files, spacing and typography constants)

If in doubt, run it. False positives are cheap, missed regressions are not.

### How to run

1. Start the **baseline (X)** from the parent/base branch and the **comparison (Y)** from the current issue branch
2. Use the `visual-comparison` skill. It discovers Mixpanel-tracked components and screenshots critical paths
3. The skill writes screenshots and ImageMagick diff images to `.visual-comparison/`

### Where to store results

After the comparison completes, **move** (not copy) the `.visual-comparison/` directory into the state directory for the current issue:

```
.state/__STATE_NAME__/visual-comparison/<issue-number>/
  x/
  y/
  diff/
```

**Do NOT commit these files.** They exist for inspection only, so reviewers and the agent can check UI parity. They stay in the state directory and never reach the remote.

### Interpreting results

- 0 differing pixels on all routes means UI parity is confirmed. Proceed normally
- Non-zero diffs mean you inspect the diff images. If the differences are intentional (the issue's goal was to change the UI), note that in the PR description. If unexpected, investigate and fix before pushing

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

Max **2 open PRs per project**, excluding the stacked draft PR, which does not count toward the limit. Check with `gh pr list --state open --author @me --search "head:project-__PROJECT_NUMBER__/" | wc -l`

At 2 or more: push the branch but don't create a PR. Track it in `./.state/__STATE_NAME__/deferred-prs.json`:
```json
{"deferred": [{"branch": "project-__PROJECT_NUMBER__/42-fix-login", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge or close.

**Stacked draft PR (mandatory).** Because PRs are stacked, the **tip of the stack** already contains all project changes. Maintain a single **draft PR** from the tip branch targeting `master` so reviewers can see the full scope of work. **The stacked PR MUST be reviewed, updated, and kept healthy.** It is not a fire-and-forget artifact.

1. The stack PR is a draft PR from the **latest project branch** (the tip of the chain) targeting `master`. No separate stack branch or merge step is needed
2. Push the tip branch and open (or update) a **draft** PR:
   ```
   gh pr create --draft --base master --title "chore(*): Stack - project-__PROJECT_NUMBER__" \
     --body "$(cat <<'EOF'
   ## Stacked changes

   This draft PR shows the combined diff of all project branches.
   **Do not merge this PR directly.** Individual PRs in the chain will merge in order.

   ### Branch chain (in order)
   - [ ] `project-__PROJECT_NUMBER__/<branch-1>` (PR #<pr>): #<issue> <title>
   - [ ] `project-__PROJECT_NUMBER__/<branch-2>` (PR #<pr>, deferred): #<issue> <title>
   - [ ] `project-__PROJECT_NUMBER__/<branch-3>` (no PR yet): #<issue> <title>
   ...

   ### Process

   Each branch goes through the following phases before merging:

   **Phase 1, PRD refresh.** Read the project board, sync all incomplete sprint issues into `prd.json`, and identify the next issue to implement.

   **Phase 2, PR review.** For every open PR, including this stacked PR: address all reviewer comments (including nits), fix failing CI, resolve merge conflicts, verify stack integrity (correct base branches, `master` merged if more than a week stale), and backpropagate fixes from child PRs to their originating parent.

   **Phase 3, implementation.** Pick the highest-priority pending issue, branch off the tip of the stack, implement against all acceptance criteria, run typecheck and tests, commit, push, and open a draft PR targeting the previous branch. Verify stacking is correct before moving on.

   **Phase 4, merge queue and closure.** Monitor PRs entering the merge queue. If a merge-queue CI check fails on an integration problem with other queued PRs, investigate and fix. When a PR merges, remove the issue from the PRD and update the stack.

   **Stack validation, on every new branch or merge:** (1) migrations apply cleanly in sequence, (2) the tip branch builds and passes typecheck and lint, (3) tests pass on the tip. Trace failures to the originating branch, fix them there, and merge into all downstream branches.
   EOF
   )"
   ```
   **The stacked PR body MUST list ALL project branches in the chain**, not only branches with open PRs. Include branches with deferred PRs, branches where PRs haven't been created yet, and branches whose PRs have already merged. Annotate each entry with its PR status: `(PR #<n>)`, `(PR #<n>, merged)`, `(deferred)`, or `(no PR yet)`. Get the full branch list via `git branch -r --list 'origin/project-__PROJECT_NUMBER__/*'` and cross-reference `prd.json` for issue metadata.
   If the draft PR already exists, update its base to the latest tip branch and edit the body: `gh pr edit <stack-pr> --body ...`
3. Track the stack PR in `./.state/__STATE_NAME__/deferred-prs.json`:
   ```json
   {"stack_pr": {"number": 99, "branch": "project-__PROJECT_NUMBER__/<tip-branch>"}, "deferred": [...]}
   ```
4. When a PR at the base of the chain merges, GitHub retargets the next PR in the chain to `master`. Update the stack PR to point at the new tip if needed. Close the stack PR when no project branches remain
5. **During Phase 2, the stacked PR is a first-class review target:**
   - Fetch and address all comments on the stacked PR (`gh pr view <stack-pr> --comments` and `gh api repos/{owner}/{repo}/pulls/{stack-pr}/comments`)
   - Fix any failing CI checks on the stacked PR. Failures here usually mean an integration problem between branches
   - Backpropagate fixes. When a stacked PR comment or CI failure reveals an issue, trace it to the originating feature branch, fix it there, then merge into all downstream branches in order. Never fix an issue only in the tip. The fix must land in the source branch so downstream branches pick it up on merge

## Stack validation

Because PRs stack additively, the tip branch already contains all changes. Validate the tip branch after adding a new branch to the chain or after merging. If a check fails, fix the originating branch and merge into downstream.

### 1. Migrations are applicable

Database migrations across the chain must apply cleanly in sequence without conflicts.

- No duplicate migration timestamps or filenames. Since each branch builds on the prior one, migrations should already be ordered. Verify no collisions exist
- Migrations apply in order. If the project has a migration runner (`just migrate`, `diesel migration run`, `sqlx migrate run`, `yarn migrate`), run it against a clean database. Without a runner, verify the SQL files are syntactically valid and that later migrations don't reference objects that haven't been created yet
- No conflicting schema changes. Check that no two branches in the chain modify the same table or column in incompatible ways

### 2. Tip branch builds

Enter the Nix dev shell and run the standard build and typecheck commands on the tip branch:

- Run the project's typecheck (`just typecheck`, `cargo check`, `tsc --noEmit`, `nix build`)
- Run the project's linter if one exists (`just lint`, `cargo clippy`)
- If either fails, find which branch in the chain introduced the problem, fix it there, then merge into all downstream branches

### 3. Tests pass

Run the project's test suite on the tip branch (`just test`, `cargo test`, `yarn test`). If tests fail:

- Work out whether the failure is a genuine integration problem or pre-existing
- Fix it in the originating branch, then merge into downstream
- Pre-existing failures that also exist on `master` can be ignored

**Do not push a tip branch that fails validation.** The stack PR exists to show reviewers that all in-flight work integrates cleanly.

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

Output `<promise>COMPLETE</promise>` when any of these holds:

1. Every issue across all sprints in `prd.json` has a status other than `pending` or `in-progress`, so all are `pr-created`, `revised`, or `skipped`, **and no PRs are open or in the merge queue**, meaning all work is merged or skipped
2. The PRD has zero sprints or zero issues
3. The GitHub project has no unclaimed, incomplete issues. Re-check via `gh project item-list`. If all remaining items are `Done` or assigned to someone else, the project is complete

**Do NOT emit `COMPLETE` if any PRs are still open, awaiting review, or in the merge queue.** The project is not done until all PRs have landed.

Otherwise, after handling one issue, end the task **without** outputting `<promise>COMPLETE</promise>`. The outer loop starts the next iteration immediately.
