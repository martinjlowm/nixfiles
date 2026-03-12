# Agent Instructions

## Workflow

1. Read `./.state/__SPEC__/prd.json` (from `./specs/__SPEC__.md`) and `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
2. **Review PR feedback for all stories** (even if `passes: true`):
   - Fetch comments via `gh pr view --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment — including nits, style suggestions, and minor feedback. Nothing gets ignored; skip only if PR is closed
   - **Exception — non-actionable comments:** Skip one-statement comments that are purely observational and don't request any change (e.g., "Interesting feature!", "Nice approach", "Cool"). These require no response or action
   - **Tone in comment replies:** Only comment on actions taken (e.g., "Fixed", "Updated to use X instead"). Do NOT engage in conversational banter, pick up on jokes or humorous remarks, or attempt to be witty. Keep replies strictly factual and action-oriented
   - **Attribution:** Prefix all PR comments with `🤖 Robotto:`
   - **Self-loop prevention:** Skip any comment that starts with `🤖 Robotto:` — these are from the agent itself. Never respond to your own comments
   - **Code changes require tests:** When implementing code changes in response to review feedback, you MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
   - **References must be accurate:** When commenting on code or adding inline documentation, only reference actual implementation details you have verified. Prefer linking to source code (with the correct tagged version, e.g., `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`) over docs.rs or other generated documentation — docs can drift from the real implementation. Never cite a function's behavior based on documentation alone; read the source to confirm
   - Rebase on base-branch (or origin/master if merged)
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for passing stories too** — if any required check has failed or been cancelled, set `passes: false`
   - **Check for merge conflicts on every PR** (even passing ones): `gh pr view <pr> --json mergeable` — if `mergeable` is `CONFLICTING`, set `passes: false` and resolve the conflicts by rebasing on the base branch
   - Set `passes: false` if unaddressed feedback (including nits), CI failures, or merge conflicts remain
3. Set up worktree: branch `[SPEC_SLUG]/[STORY]` off dependent branch (or origin/master). Run: `worktree <name> --base <base-branch>`
4. Enter Nix dev shell before any work (generates pre-commit hooks)
5. Pick highest priority story with `passes: false` and **no running CI** (`gh pr checks <pr> --json name,state` — skip if any state is `PENDING`; if all blocked, **end the task immediately**)
6. Implement/revise that **one** story. Verify **every item** in `acceptanceCriteria` is met before moving on. Run typecheck and tests for affected projects
7. Update AGENTS.md with learnings
8. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` referencing base-branch PR. Component: specific project or `*` for many
9. Push (NEVER force push — merge upstream first). Create draft PR respecting **PR Limit**. The PR description must include **motivation** (why this change is needed — the problem it solves or the value it adds) before describing what was implemented. Re-evaluate PR title and description to reflect the latest state — incorporate learnings from progress.txt and AGENTS.md so the PR accurately describes what was actually implemented, not the original plan
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

## PR Limit

Max **5 open PRs per spec**. Check: `gh pr list --state open --author @me --search "head:__SPEC_SLUG__/" | wc -l`

If ≥5: push branch but don't create PR. Track in `./.state/__SPEC__/deferred-prs.json`:
```json
{"deferred": [{"branch": "spec/story-6", "pushed_at": "<ISO>", "reason": "PR limit reached"}]}
```
Create deferred PRs when existing ones merge/close.

## PR Review Tracking

Address every comment (implement or explain disagreement). Track in `./.state/__SPEC__/review-state.json`:
```json
{"pr_number": 123, "last_addressed_comment_id": "IC_abc", "last_addressed_at": "<ISO>", "addressed_comments": [], "pending_comments": []}
```
Re-fetch after push — new comments may arrive.

### Story Completion Criteria

`passes: true` requires: all review comments addressed — including nits (`pending_comments` empty) + all CI passed + no merge conflicts + changes pushed + PR title/description accurate.

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
