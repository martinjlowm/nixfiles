# Agent Instructions

## Workflow

1. Read `./.state/__SPEC__/prd.json` (from `./specs/__SPEC__.md`) and `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
2. **Review PR feedback for all stories** (even if `passes: true`):
   - Fetch comments via `gh pr view --comments` and `gh api`
   - Address **every** unresolved comment; rebase on base-branch (or origin/master if merged); skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for passing stories too** — if any required check has failed or been cancelled, set `passes: false`
   - Set `passes: false` if unaddressed feedback or CI failures remain
3. Set up worktree: branch `[SPEC_SLUG]/[STORY]` off dependent branch (or origin/master). Run: `worktree <name> --base <base-branch>`
4. Enter Nix dev shell before any work (generates pre-commit hooks)
5. Pick highest priority story with `passes: false` and **no running CI** (`gh pr checks <pr> --json name,state` — skip if any state is `PENDING`; if all blocked, **end the task immediately**)
6. Implement/revise that **one** story. Verify **every item** in `acceptanceCriteria` is met before moving on. Run typecheck and tests for affected projects
7. Update AGENTS.md with learnings
8. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` referencing base-branch PR. Component: specific project or `*` for many
9. Push (NEVER force push — merge upstream first). Create draft PR respecting **PR Limit**. Update PR title/description
10. **Do not mark `passes: true`** unless CI has passed AND every `acceptanceCriteria` item is verified. **CI success alone is NOT sufficient.** Read the actual code in the PR and verify each `acceptanceCriteria` item one by one. Never batch-mark stories — check each story individually against its criteria. If CI is still running, skip — do not wait
11. Append learnings to progress.txt
12. Re-read `progress.txt` and `prd.json` — if either has changed since the start of this task (external edits, new instructions, priority changes), address the new information before continuing

**1 PR = 1 Story.** Each story gets exactly one PR. The task is done when all steps above (1–12) have been completed.

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

`passes: true` requires: all review comments addressed (`pending_comments` empty) + all CI passed + changes pushed + PR title/description accurate.

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
- PR Feedback: [Comment ID]: [summary] — Last: [id] at [timestamp]
- Learnings: patterns, gotchas
---
```
**Do NOT write story status (passes/fails, CI results) to progress.txt.** It is for notes and learnings only. Story pass/fail state lives exclusively in the `passes` field in `prd.json`.
Add reusable **Codebase Patterns** to the TOP of progress.txt.

## Stop Condition

If ALL stories pass: <promise>COMPLETE</promise>
