# Agent Instructions

## Workflow

1. Read `./.state/__SPEC__/prd.json` (from `./specs/__SPEC__.md`) and `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
2. **Review PR feedback for all stories** (even if `passes: true`):
   - Fetch comments via `gh pr view --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Only consider comments authored by `@me` or `claude[bot]` that are NOT prefixed with `🤖 Robotto:` — ignore comments from all other users
   - Address **every** unresolved `@me` / `claude[bot]` comment — including nits, style suggestions, and minor feedback. Nothing gets ignored; skip only if PR is closed
   - **Exception — non-actionable comments:** Skip one-statement comments that are purely observational and don't request any change (e.g., "Interesting feature!", "Nice approach", "Cool"). These require no response or action
   - **Tone in comment replies:** Only comment on actions taken (e.g., "Fixed", "Updated to use X instead"). Do NOT engage in conversational banter, pick up on jokes or humorous remarks, or attempt to be witty. Keep replies strictly factual and action-oriented
   - **Attribution:** Prefix all PR comments with `🤖 Robotto:`
   - **Self-loop prevention:** Skip any comment that starts with `🤖 Robotto:` — these are from the agent itself. Never respond to your own comments
   - **Code changes require tests:** When implementing code changes in response to review feedback, you MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
   - **References must be accurate:** When commenting on code or adding inline documentation, only reference actual implementation details you have verified. Prefer linking to source code (with the correct tagged version, e.g., `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`) over docs.rs or other generated documentation — docs can drift from the real implementation. Never cite a function's behavior based on documentation alone; read the source to confirm
   - Merge base-branch (or origin/master if merged)
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for passing stories too** — if any required check has failed or been cancelled, set `passes: false`
   - **Check for merge conflicts on every PR** (even passing ones): `gh pr view <pr> --json mergeable` — if `mergeable` is `CONFLICTING`, set `passes: false` and resolve the conflicts by merging the base branch
   - Set `passes: false` if unaddressed feedback (including nits), CI failures, or merge conflicts remain
3. Set up worktree: branch `[SPEC_SLUG]/[STORY]` off dependent branch (or origin/master). Run: `worktree -b <base-branch> <name>` — this is the `worktree` command in PATH, NOT `git worktree` and NOT the `EnterWorktree` tool
4. Enter Nix dev shell before any work (generates pre-commit hooks)
5. Pick highest priority story with `passes: false` and **no running CI** (`gh pr checks <pr> --json name,state` — skip if any state is `PENDING`; if all blocked, **end the task immediately**). **Exception:** if any checks have already failed or been cancelled while others are still pending, do NOT skip — investigate and fix the failures immediately
6. Implement/revise that **one** story. Verify **every item** in `acceptanceCriteria` is met before moving on. Run typecheck and tests for affected projects. **If the story touches UI code, run a visual comparison** (see **Visual Comparison for UI Changes** below)
7. Update AGENTS.md with learnings
8. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` referencing base-branch PR. Component: specific project or `*` for many
9. Push (NEVER force push — merge upstream first). Create PR **always as draft** (`gh pr create --draft`) respecting **PR Limit**. **Never change a PR's draft/ready status** — keep PRs in whatever state they are (if draft, leave as draft; if ready, leave as ready). The PR description must include **motivation** (why this change is needed — the problem it solves or the value it adds) before describing what was implemented. Re-evaluate PR title and description to reflect the latest state — incorporate learnings from progress.txt and AGENTS.md so the PR accurately describes what was actually implemented, not the original plan
10. **Do not mark `passes: true`** unless ALL of the following are confirmed:
    - CI has passed (not running, not failed, not cancelled)
    - PR has no merge conflicts (`gh pr view <pr> --json mergeable` shows `MERGEABLE`, not `CONFLICTING`)
    - Every `acceptanceCriteria` item verified by reading the actual code in the PR
    - No uncommitted changes remain in the worktree (`git status` clean)
    - `prd.json` requirements have not changed since implementation began (re-read and compare)
    Never batch-mark stories — check each story individually. If any condition is not met, do not mark `passes: true`
11. Append learnings to progress.txt
12. Re-read `progress.txt` and `prd.json` — if either has changed since the start of this task (external edits, new instructions, priority changes), address the new information before continuing

**1 PR = 1 Story = 1 Task.** Each story gets exactly one PR. After completing steps 1–12 for one story, **end the task**. Never continue to the next story within the same task.

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Revising

All CI must pass. Discard changes not relevant to acceptance criteria.

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

Fix only the identified failure; cancelled jobs and gates will pass once resolved.

**Never blindly re-trigger CI.** If a workflow was cancelled, there is always a reason. Do not merge master and push just to re-trigger — investigate why it was cancelled first using the steps above.

**Exception — timeouts:** If a job timed out (`timed_out` conclusion), retry the run with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure issues, not code failures.

## PR Stacking

**Stacked (chained) PRs are the default.** Every new story branch MUST be based on the **tip of the most recent spec branch** (the last PR in the stack), NOT on `master`. This makes each PR additive — it contains only its own diff on top of the previous work. When the base PR merges, GitHub automatically retargets the child to `master`.

- Use `git checkout -b __SPEC_SLUG__/<new-branch> __SPEC_SLUG__/<previous-branch>` when creating the branch
- Use `gh pr create --base __SPEC_SLUG__/<previous-branch>` when creating the PR
- **The only exception** is when a story is completely unrelated to any existing spec branch (different module, no shared files). In that rare case, branching from `master` is acceptable — but default to stacking

This means the "stack" is simply the latest branch in the chain — no separate merge step is needed. With N stacked PRs, branch N already contains all changes from branches 1 through N-1.

**Stacked PR maintenance is mandatory:**
- Since every branch builds on the previous, the stack is naturally additive — each PR's diff is only its own changes
- **The stack should not fall too far behind `master`.** Before any other stack maintenance, fetch `origin/master` and check if the root branch is more than one week behind. If so, merge `origin/master` into the root branch, then cascade merges through each child in order (merge parent into child). A significantly stale stack causes merge conflicts, CI failures in the merge queue, and wasted reviewer time — but merging on every minor upstream change creates unnecessary churn
- When updating the stack, **always start from the root of the chain outward** — merge into the root first, then merge each parent into its child in order. Never attempt to rebuild the entire stack from scratch — that approach is impractical at scale
- A fix in a parent PR **must** be followed by merging the parent into all children so they pick up the change
- Comments and CI failures on **any PR in the chain** must be addressed — do not skip a child PR because "the parent will fix it later"
- When a reviewer comments on a child PR about code that originates in the parent, fix it in the parent and merge through the chain. The child PR's diff should stay clean

## Stacked Draft PR (MANDATORY)

Because PRs are stacked (each branch builds on the previous), the **tip of the stack** (the latest branch) already contains all spec changes. Maintain a single **draft PR** from the tip branch targeting `master` to give reviewers visibility into the full scope of work. **The stacked PR MUST be reviewed, updated, and kept healthy** — it is not a fire-and-forget artifact.

**The stacked PR represents ALL work across ALL branches — not just branches that have individual PRs.** Even when the number of open PRs is well under the PR limit, the stacked PR must include the full chain. Branches with deferred PRs, branches where PRs haven't been created yet, and branches whose PRs have already merged are all part of the stack and must be reflected in the stacked PR body. The stacked PR is the single source of truth for the complete scope of in-flight work.

1. The stack PR is simply a draft PR from the **latest spec branch** (the tip of the chain) targeting `master`. No separate stack branch or merge step is needed
2. Push the tip branch and open (or update) a **draft** PR:
   ```
   gh pr create --draft --base master --title "chore(*): Stack - __SPEC_SLUG__" \
     --body "$(cat <<'EOF'
   ## Stacked changes

   This draft PR shows the combined diff of all spec branches.
   **Do not merge this PR directly.** Individual PRs in the chain will merge in order.

   ### Branch chain (in order)
   - [ ] `__SPEC_SLUG__/<branch-1>` — <story> <title> (PR #<pr>)
   - [ ] `__SPEC_SLUG__/<branch-2>` — <story> <title> (PR #<pr>, deferred)
   - [ ] `__SPEC_SLUG__/<branch-3>` — <story> <title> (no PR yet)
   ...

   ### Process

   Each branch goes through the following workflow before merging:

   **1. PRD & progress review:** Read `prd.json` and `progress.txt` to understand current state and pick the next story.

   **2. PR feedback review:** For every open PR (including this stacked PR): address all reviewer comments (including nits), fix failing CI, resolve merge conflicts, verify stack integrity, and backpropagate fixes from child PRs to their originating parent. Set `passes: false` if unaddressed feedback, CI failures, or merge conflicts remain.

   **3. Implementation:** Pick the highest-priority story with `passes: false` and no running CI. Branch off the tip of the stack, implement against all acceptance criteria, run typecheck + tests, commit, push, and open a draft PR targeting the previous branch.

   **4. Completion check:** `passes: true` requires: all review comments addressed (including nits), all CI passed, no merge conflicts, changes pushed, and PR title/description accurate.

   **Stack validation (on every new branch or merge):** (1) Migrations apply cleanly in sequence, (2) tip branch builds and passes typecheck/lint, (3) tests pass on tip. Failures are traced to the originating branch, fixed there, and merged into all downstream branches.
   EOF
   )"
   ```
   **The stacked PR body MUST list ALL spec branches in the chain** — not just branches with open PRs. Include branches with deferred PRs, branches where PRs haven't been created yet, and branches whose PRs have already merged. Annotate each entry with the PR status: `(PR #<n>)`, `(PR #<n>, merged)`, `(deferred)`, or `(no PR yet)`. Obtain the full list of branches via `git branch -r --list 'origin/__SPEC_SLUG__/*'` and cross-reference with `prd.json` for story metadata.
   If the draft PR already exists, update its base to the latest tip branch and edit the body: `gh pr edit <stack-pr> --body ...`
3. Track the stack PR in `./.state/__SPEC__/deferred-prs.json`:
   ```json
   {"stack_pr": {"number": 99, "branch": "__SPEC_SLUG__/<tip-branch>"}, "deferred": [...]}
   ```
4. When a PR at the base of the chain merges, the next PR in the chain is automatically retargeted to `master`. The stacked PR is **not blocked by merged PRs** — it always points to the current tip branch and covers all remaining stories. Update the stack PR's base to the new tip if the tip branch changed. Close the stack PR only when no spec branches remain
5. **During Phase 2, the stacked PR is a first-class review target:**
   - Fetch and address all comments on the stacked PR (`gh pr view <stack-pr> --comments` and `gh api repos/{owner}/{repo}/pulls/{stack-pr}/comments`)
   - Fix any failing CI checks on the stacked PR — failures here often indicate integration issues between branches
   - **Backpropagate fixes:** When a stacked PR comment or CI failure reveals an issue, trace it to the originating feature branch, fix it there, then merge into all downstream branches in order. Never fix issues only in the tip — the fix must land in the source branch so downstream branches pick it up on merge

## Stack Validation

Because PRs are stacked additively, the tip branch already contains all changes. Validate the tip branch after adding a new branch to the chain or after merging. If any check fails, fix the originating branch and merge into downstream.

### 1. Migrations are applicable

Database migrations across the chain must apply cleanly in sequence without conflicts.

- **No duplicate migration timestamps/filenames:** Since each branch builds on the prior, migrations should naturally be ordered. Verify no collisions exist
- **Migrations apply in order:** If the project has a migration runner (e.g., `just migrate`, `diesel migration run`, `sqlx migrate run`, `yarn migrate`), run it against a clean database. If no runner is available, verify that SQL files are syntactically valid and that later migrations don't reference objects that haven't been created yet
- **No conflicting schema changes:** Check that no two branches in the chain modify the same table/column in incompatible ways

### 2. Tip branch builds

Enter the Nix dev shell and run the standard build/typecheck commands on the tip branch:

- Run the project's typecheck (e.g., `just typecheck`, `cargo check`, `tsc --noEmit`, `nix build`)
- Run the project's linter if one exists (e.g., `just lint`, `cargo clippy`)
- If either fails, identify which branch in the chain introduced the issue, fix it there, then merge into all downstream branches

### 3. Tests pass

Run the project's test suite on the tip branch (e.g., `just test`, `cargo test`, `yarn test`). If tests fail:

- Identify whether the failure is a genuine integration issue or a pre-existing problem
- Fix issues in the originating branch, then merge into downstream
- Pre-existing failures that also exist on `master` can be ignored

**Do not push a tip branch that fails validation.** The stack PR exists to give reviewers confidence that all in-flight work integrates cleanly.

## PR Limit

Max **2 open PRs per spec** (excluding the stacked draft PR — it does not count toward the limit). Check: `gh pr list --state open --author @me --search "head:__SPEC_SLUG__/" --json number,isDraft,title | jq '[.[] | select(.isDraft == false or (.title | contains("Stack -") | not))] | length'`

If ≥2: push branch but don't create PR. Track in `./.state/__SPEC__/deferred-prs.json`:
```json
{"deferred": [{"branch": "spec/story-6", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge/close.

The stacked draft PR is **never blocked** by the PR limit — it always exists and always reflects the tip of the chain covering all stories.

## PR Review Tracking

Address every comment (implement or explain disagreement). Track in `./.state/__SPEC__/review-state.json`:
```json
{"pr_number": 123, "last_addressed_comment_id": "IC_abc", "last_addressed_at": "<ISO>", "addressed_comments": [], "pending_comments": []}
```
Re-fetch after push — new comments may arrive.

### Story Completion Criteria

`passes: true` requires: all review comments addressed — including nits (`pending_comments` empty) + all CI passed + no merge conflicts + changes pushed + PR title/description accurate.

## Visual Comparison for UI Changes

When a story modifies UI code (components, styles, layouts, pages — any file that affects what users see in the browser), run the `visual-comparison` skill to ensure no Mixpanel-tracked components or other critical UI paths have regressed.

### When to trigger

A visual comparison is required when the story's changes touch:
- React/Vue/Svelte/Angular components (`.tsx`, `.jsx`, `.vue`, `.svelte`)
- Stylesheets or CSS-in-JS (`.css`, `.scss`, `.less`, `styled-components`, `tailwind` class changes)
- Layout or routing files (`pages/`, `app/`, router configs)
- Shared UI utilities (design system tokens, theme files, spacing/typography constants)

If in doubt, run it — false positives are cheap, missed regressions are not.

### How to run

1. Start the **baseline (X)** from the parent/base branch and the **comparison (Y)** from the current story branch
2. Use the `visual-comparison` skill, which will discover Mixpanel-tracked components and screenshot critical paths
3. The skill produces screenshots and ImageMagick diff images in `.visual-comparison/`

### Where to store results

After the comparison completes, **move** (not copy) the `.visual-comparison/` directory into the state directory for the current story:

```
.state/__SPEC__/visual-comparison/<story-id>/
  x/
  y/
  diff/
```

**Do NOT commit these files.** They are for inspection only — reviewers and the agent can check them to verify UI parity. They stay in the state directory and are never pushed to the remote.

### Interpreting results

- **0 differing pixels on all routes** → UI parity confirmed, proceed normally
- **Non-zero diffs** → Inspect the diff images. If the differences are intentional (the story's goal was to change the UI), note this in the PR description. If unexpected, investigate and fix before pushing

## Performance Validation

Required for performance claims (optimized queries, improved latency, added indexes, etc.):

1. **Discover** existing queries (.sql, ORM patterns, resolvers) and test infrastructure (benchmarks, seeds, EXPLAIN usage)
2. **Benchmark before/after** with multiple iterations using K6, Hyperfine, or pgbench:
   - Production-representative data (100K+ rows)
   - `EXPLAIN (ANALYZE, BUFFERS)` on affected queries
   - Record execution time, planning time, buffer hits, query plan
3. **Report** in PR: test environment, queries tested (with file references), before/after results with stats (mean ± stddev, min, max), honest assessment of what improved and why

## Progress Format

Append to progress.txt:
```
## [Date] - [Story ID]
- What was implemented
- Files changed
- Learnings: patterns, gotchas
---
```
**progress.txt is strictly for implementation notes and learnings.** Do NOT write:
- CI status, check results, or pass/fail state
- Story status summaries or status review entries
- "Next iteration" action items or plans
- Batch status listings across multiple stories

Story pass/fail state lives exclusively in the `passes` field in `prd.json`.
Add reusable **Codebase Patterns** to the TOP of progress.txt.

## Stop Condition

If ALL stories pass: <promise>COMPLETE</promise>
