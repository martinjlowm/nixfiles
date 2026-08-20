# Agent instructions

> Note on priority handoffs. If this prompt begins with a **PRIORITY HANDOFF
> INSTRUCTIONS** block, those instructions were handed off by the previous
> process and **take precedence over everything in this workflow**. Follow them
> first. Use the workflow below only for details the handoff leaves unspecified,
> and only where it does not conflict with the handoff.

## Workflow

1. Read `./.state/__SPEC__/prd.json` (from `./specs/__SPEC__.md`) and `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
2. Review PR feedback for all stories, even those with `passes: true`:
   - Fetch comments via `gh pr view --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Only consider comments authored by `@me` or `claude[bot]` that are NOT prefixed with `🤖 Robotto:`. Ignore comments from all other users
   - Address **every** unresolved `@me` / `claude[bot]` comment, including nits, style suggestions, and minor feedback. Nothing gets ignored. Skip only if the PR is closed
   - Non-actionable comments are the exception. Skip one-statement comments that are purely observational and request no change ("Interesting feature!", "Nice approach", "Cool"). They need no response or action
   - In replies, report only the action taken ("Fixed", "Updated to use X instead"). No conversational banter, no picking up on jokes or humorous remarks, no wit. Keep replies factual
   - Prefix all PR comments with `🤖 Robotto:`
   - Skip any comment that starts with `🤖 Robotto:`. Those come from the agent itself. Never respond to your own comments
   - Code changes require tests. When implementing changes in response to review feedback, you MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
   - Keep references accurate. When commenting on code or adding inline documentation, only reference implementation details you have verified. Link to source code with the correct tagged version, e.g. `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`, rather than docs.rs or other generated documentation, which drifts from the real implementation. Never cite a function's behavior from documentation alone. Read the source to confirm
   - Merge base-branch (or origin/master if merged)
   - Fix failing CI checks (see "Cancelled workflows"; warnings aren't failures)
   - Check CI for passing stories too. If any required check has failed or been cancelled, set `passes: false`
   - Check for merge conflicts on every PR, even passing ones: `gh pr view <pr> --json mergeable`. If `mergeable` is `CONFLICTING`, set `passes: false` and resolve the conflicts by merging the base branch
   - Set `passes: false` if unaddressed feedback (including nits), CI failures, or merge conflicts remain
3. Set up working branch `[SPEC_SLUG]/[STORY]` off the dependent branch (or origin/master).
   - Bare repo: run `worktree -b <base-branch> <name>`. This is the `worktree` command in PATH, NOT `git worktree` and NOT the `EnterWorktree` tool
   - Regular repo: `git checkout -b <name> <base-branch>`
4. Enter the Nix dev shell before any work. It generates the pre-commit hooks
5. Pick the highest priority story with `passes: false` and **no running CI** (`gh pr checks <pr> --json name,state`, skip if any state is `PENDING`; if all are blocked, **end the task immediately**). Exception: if some checks have already failed or been cancelled while others are still pending, do NOT skip. Investigate and fix the failures immediately
6. Implement or revise that **one** story. Verify **every item** in `acceptanceCriteria` before moving on. Run typecheck and tests for affected projects. If the story touches UI code, run a visual comparison (see "Visual comparison for UI changes")
7. Update AGENTS.md with learnings
8. Commit as `[feat|fix|chore]([Component]): [ID] - [Title]`, referencing the base-branch PR. Component is the specific project, or `*` for many
9. Push. NEVER force push, merge upstream first. Create the PR **always as draft** (`gh pr create --draft`), respecting the PR limit. **Never change a PR's draft/ready status.** Leave a draft as draft and a ready PR as ready. The description must state the motivation, the problem it solves or the value it adds, before describing what was implemented. Re-evaluate the title and description against the latest state, folding in learnings from progress.txt and AGENTS.md, so the PR describes what was actually implemented rather than the original plan
10. **Do not mark `passes: true`** unless all of the following are confirmed:
    - CI has passed (not running, not failed, not cancelled)
    - The PR has no merge conflicts (`gh pr view <pr> --json mergeable` shows `MERGEABLE`, not `CONFLICTING`)
    - Every `acceptanceCriteria` item verified by reading the actual code in the PR
    - No uncommitted changes remain (`git status` clean)
    - `prd.json` requirements have not changed since implementation began (re-read and compare)
    Never batch-mark stories. Check each one individually. If any condition fails, do not mark `passes: true`
11. Append learnings to progress.txt
12. Re-read `progress.txt` and `prd.json`. If either changed since this task started (external edits, new instructions, priority changes), address the new information before continuing

**1 PR = 1 story = 1 task.** Each story gets exactly one PR. After completing steps 1-12 for one story, **end the task**. Never continue to the next story within the same task.

**NEVER wait or poll for CI.** Check CI status once. If checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Revising

All CI must pass. Discard changes not relevant to acceptance criteria.

### Cancelled workflows

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

Timeouts are the exception. If a job timed out (`timed_out` conclusion), retry it with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure problems, not code failures.

## PR stacking

**Stacked (chained) PRs are the default.** Every new story branch MUST be based on the **tip of the most recent spec branch** (the last PR in the stack), not on `master`. That makes each PR additive. It contains only its own diff on top of the previous work. When the base PR merges, GitHub retargets the child to `master`.

- Use `git checkout -b __SPEC_SLUG__/<new-branch> __SPEC_SLUG__/<previous-branch>` when creating the branch
- Use `gh pr create --base __SPEC_SLUG__/<previous-branch>` when creating the PR
- **The only exception** is a story completely unrelated to any existing spec branch (different module, no shared files). Branching from `master` is acceptable then, but default to stacking

So the "stack" is just the latest branch in the chain, and no separate merge step is needed. With N stacked PRs, branch N already contains all changes from branches 1 through N-1.

**Stacked PR maintenance is mandatory:**
- Since every branch builds on the previous, the stack is additive and each PR's diff is only its own changes
- **The stack should not fall too far behind `master`.** Before any other stack maintenance, fetch `origin/master` and check whether the root branch is more than one week behind. If so, merge `origin/master` into the root branch, then cascade merges through each child in order (merge parent into child). A stale stack causes merge conflicts, CI failures in the merge queue, and wasted reviewer time, but merging on every minor upstream change creates churn
- When updating the stack, **always start from the root of the chain outward**. Merge into the root first, then merge each parent into its child in order. Never rebuild the whole stack from scratch. That is impractical at scale
- A fix in a parent PR **must** be followed by merging the parent into all children so they pick up the change
- Comments and CI failures on **any PR in the chain** must be addressed. Do not skip a child PR because "the parent will fix it later"
- When a reviewer comments on a child PR about code that originates in the parent, fix it in the parent and merge through the chain. The child PR's diff stays clean

## Stacked draft PR (mandatory)

Because PRs are stacked, the **tip of the stack** already contains all spec changes. Maintain a single **draft PR** from the tip branch targeting `master` so reviewers can see the full scope of work. **The stacked PR MUST be reviewed, updated, and kept healthy.** It is not a fire-and-forget artifact.

**The stacked PR represents ALL work across ALL branches, not only branches that have individual PRs.** Even when the number of open PRs is well under the PR limit, the stacked PR must cover the full chain. Branches with deferred PRs, branches where PRs haven't been created yet, and branches whose PRs have already merged are all part of the stack and must appear in the stacked PR body. The stacked PR is the single source of truth for the complete scope of in-flight work.

1. The stack PR is a draft PR from the **latest spec branch** (the tip of the chain) targeting `master`. No separate stack branch or merge step is needed
2. Push the tip branch and open (or update) a **draft** PR:
   ```
   gh pr create --draft --base master --title "chore(*): Stack - __SPEC_SLUG__" \
     --body "$(cat <<'EOF'
   ## Stacked changes

   This draft PR shows the combined diff of all spec branches.
   **Do not merge this PR directly.** Individual PRs in the chain will merge in order.

   ### Branch chain (in order)
   - [ ] `__SPEC_SLUG__/<branch-1>` (PR #<pr>): <story> <title>
   - [ ] `__SPEC_SLUG__/<branch-2>` (PR #<pr>, deferred): <story> <title>
   - [ ] `__SPEC_SLUG__/<branch-3>` (no PR yet): <story> <title>
   ...

   ### Process

   Each branch goes through the following workflow before merging:

   **1. PRD and progress review.** Read `prd.json` and `progress.txt` to understand current state and pick the next story.

   **2. PR feedback review.** For every open PR, including this stacked PR: address all reviewer comments (including nits), fix failing CI, resolve merge conflicts, verify stack integrity, and backpropagate fixes from child PRs to their originating parent. Set `passes: false` if unaddressed feedback, CI failures, or merge conflicts remain.

   **3. Implementation.** Pick the highest-priority story with `passes: false` and no running CI. Branch off the tip of the stack, implement against all acceptance criteria, run typecheck and tests, commit, push, and open a draft PR targeting the previous branch.

   **4. Completion check.** `passes: true` requires all review comments addressed (including nits), all CI passed, no merge conflicts, changes pushed, and an accurate PR title and description.

   **Stack validation, on every new branch or merge:** (1) migrations apply cleanly in sequence, (2) the tip branch builds and passes typecheck and lint, (3) tests pass on the tip. Trace failures to the originating branch, fix them there, and merge into all downstream branches.
   EOF
   )"
   ```
   **The stacked PR body MUST list ALL spec branches in the chain**, not only branches with open PRs. Include branches with deferred PRs, branches where PRs haven't been created yet, and branches whose PRs have already merged. Annotate each entry with its PR status: `(PR #<n>)`, `(PR #<n>, merged)`, `(deferred)`, or `(no PR yet)`. Get the full branch list via `git branch -r --list 'origin/__SPEC_SLUG__/*'` and cross-reference `prd.json` for story metadata.
   If the draft PR already exists, update its base to the latest tip branch and edit the body: `gh pr edit <stack-pr> --body ...`
3. Track the stack PR in `./.state/__SPEC__/deferred-prs.json`:
   ```json
   {"stack_pr": {"number": 99, "branch": "__SPEC_SLUG__/<tip-branch>"}, "deferred": [...]}
   ```
4. When a PR at the base of the chain merges, GitHub retargets the next PR in the chain to `master`. The stacked PR is **not blocked by merged PRs**. It always points at the current tip branch and covers all remaining stories. Update its base if the tip branch changed. Close the stack PR only when no spec branches remain
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

## PR limit

Max **2 open PRs per spec**, excluding the stacked draft PR, which does not count toward the limit. Check with `gh pr list --state open --author @me --search "head:__SPEC_SLUG__/" --json number,isDraft,title | jq '[.[] | select(.isDraft == false or (.title | contains("Stack -") | not))] | length'`

At 2 or more: push the branch but don't create a PR. Track it in `./.state/__SPEC__/deferred-prs.json`:
```json
{"deferred": [{"branch": "spec/story-6", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge or close.

The stacked draft PR is **never blocked** by the PR limit. It always exists and always reflects the tip of the chain covering all stories.

## PR review tracking

Address every comment, either by implementing it or explaining the disagreement. Track in `./.state/__SPEC__/review-state.json`:
```json
{"pr_number": 123, "last_addressed_comment_id": "IC_abc", "last_addressed_at": "<ISO>", "addressed_comments": [], "pending_comments": []}
```
Re-fetch after pushing. New comments may have arrived.

### Story completion criteria

`passes: true` requires all review comments addressed, including nits (`pending_comments` empty), all CI passed, no merge conflicts, changes pushed, and an accurate PR title and description.

## Visual comparison for UI changes

When a story modifies UI code (components, styles, layouts, pages, any file that affects what users see in the browser), run the `visual-comparison` skill to check that no Mixpanel-tracked components or other critical UI paths have regressed.

### When to trigger

A visual comparison is required when the story's changes touch:
- React/Vue/Svelte/Angular components (`.tsx`, `.jsx`, `.vue`, `.svelte`)
- Stylesheets or CSS-in-JS (`.css`, `.scss`, `.less`, `styled-components`, `tailwind` class changes)
- Layout or routing files (`pages/`, `app/`, router configs)
- Shared UI utilities (design system tokens, theme files, spacing and typography constants)

If in doubt, run it. False positives are cheap, missed regressions are not.

### How to run

1. Start the **baseline (X)** from the parent/base branch and the **comparison (Y)** from the current story branch
2. Use the `visual-comparison` skill. It discovers Mixpanel-tracked components and screenshots critical paths
3. The skill writes screenshots and ImageMagick diff images to `.visual-comparison/`

### Where to store results

After the comparison completes, **move** (not copy) the `.visual-comparison/` directory into the state directory for the current story:

```
.state/__SPEC__/visual-comparison/<story-id>/
  x/
  y/
  diff/
```

**Do NOT commit these files.** They exist for inspection only, so reviewers and the agent can check UI parity. They stay in the state directory and never reach the remote.

### Interpreting results

- 0 differing pixels on all routes means UI parity is confirmed. Proceed normally
- Non-zero diffs mean you inspect the diff images. If the differences are intentional (the story's goal was to change the UI), note that in the PR description. If unexpected, investigate and fix before pushing

## Performance validation

Required for performance claims (optimized queries, improved latency, added indexes, and so on):

1. Find the existing queries (.sql, ORM patterns, resolvers) and test infrastructure (benchmarks, seeds, EXPLAIN usage)
2. Benchmark before and after with multiple iterations using K6, Hyperfine, or pgbench:
   - Production-representative data (100K+ rows)
   - `EXPLAIN (ANALYZE, BUFFERS)` on affected queries
   - Record execution time, planning time, buffer hits, query plan
3. Report in the PR: test environment, queries tested (with file references), before/after results with stats (mean ± stddev, min, max), and an honest assessment of what improved and why

## Progress format

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

Story pass/fail state lives only in the `passes` field in `prd.json`.
Add reusable **Codebase Patterns** to the TOP of progress.txt.

## Next condition (handoff)

loop2 lets the **conclusion of an iteration hand off a fresh set of prompt
instructions** to whatever process picks up next. Use it when the work you just
did has reshaped what should happen next so much that the standard workflow above
is no longer the right starting point.

### When the next condition is true

Evaluate the next condition at the **very end** of the iteration, after all other
work is done. It is true when **all** of the following hold:

1. You have finished, or deliberately stopped, the current iteration's work.
2. The next process should **not** simply re-run the standard workflow. It needs a
   different, more specific objective that you can state concretely now: a focused
   follow-up, a one-off migration, a cleanup pass, a hand-off to a different spec,
   or a narrowed scope that supersedes normal story selection.
3. You can express that objective as **self-contained instructions**, covering
   everything the next process needs, without relying on this iteration's memory.

If the next condition is **false**, do nothing special. End the task normally and
the next iteration runs the standard workflow.

### How to hand off

When the next condition is true, emit a single `<next>...</next>` block as part of
your conclusion. Everything between the tags is captured verbatim, persisted, and
injected at the **top** of the next iteration's prompt as **PRIORITY HANDOFF
INSTRUCTIONS that take precedence over this entire workflow**.

```
<next>
# Objective for the next process
<one paragraph stating the goal that overrides the standard workflow>

## Do this
1. <concrete, ordered steps the next process must follow>
2. ...

## Constraints and context
- <anything the next process needs: branch names, file paths, IDs, prior decisions>

## When to stop or hand back
- <what "done" looks like, or the condition under which the next process should
  fall back to the standard workflow or emit its own <next> block>
</next>
```

Rules for the handoff block:

- Be precedence-aware. The next process is told these instructions OVERRIDE the
  standard workflow. Only point it back to the standard workflow for details you
  deliberately leave unspecified, and say so explicitly.
- Be self-contained. Include concrete names, paths, IDs, and decisions. The next
  process does not share your conversation memory.
- One baton at a time. Emit at most one `<next>` block per iteration. Exactly the
  next iteration consumes it. If that iteration needs to keep handing off, it must
  emit its own `<next>` block.
- Do **not** wrap the standard workflow itself in `<next>`. Only the new,
  overriding instructions.
- A `<next>` handoff and `<promise>COMPLETE</promise>` are mutually exclusive. If all
  work is genuinely done, complete. If there is a redirected next step, hand off.

## Stop condition

If ALL stories pass: <promise>COMPLETE</promise>

Otherwise, if the **next condition** is true, emit a `<next>...</next>` block (see
"Next condition (handoff)" above) and end the task. The next iteration picks up
those instructions with precedence over this workflow.

Otherwise, end the task normally without any promise. The next iteration runs the
standard workflow.
