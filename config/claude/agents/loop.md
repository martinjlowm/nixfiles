# Agent Instructions

## Workflow

1. Read `./.state/__SPEC__/prd.json` (from `./specs/__SPEC__.md`) and `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
2. **Review PR feedback for all stories** (even if `passes: true`):
   - Fetch comments via `gh pr view --comments` and `gh api`
   - Address **every** unresolved comment; rebase on base-branch (or origin/master if merged); skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - Set `passes: false` if unaddressed feedback or CI failures remain
3. Set up worktree: branch `[SPEC_SLUG]/[STORY]` off dependent branch (or origin/master). Run: `worktree <name> --base <base-branch>`
4. Enter Nix dev shell before any work (generates pre-commit hooks)
5. Pick highest priority story with `passes: false` and **no running CI** (`gh pr checks <pr> --json name,state,status` — skip if any `in_progress`/`queued`/`pending`; if all blocked, **end the task immediately**)
6. Implement/revise that **one** story. Run typecheck and tests for affected projects
7. Update AGENTS.md with learnings
8. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` referencing base-branch PR. Component: specific project or `*` for many
9. Push (NEVER force push — merge upstream first). Create draft PR respecting **PR Limit**. Update PR title/description
10. **Do not mark `passes: true`** — move to next story immediately. On later iterations, re-check CI: all passed → `passes: true`; failed → fix; running → skip
11. Append learnings to progress.txt

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately. CI runs are long; your time is better spent on the next actionable story. Come back on the next iteration when results are available.

## Revising

All CI must pass. Discard changes not relevant to acceptance criteria.

### Troubleshooting Cancelled Workflows

When most/all jobs show as `cancelled`, exactly ONE job will have a non-zero exit code — that's the root cause. The rest were cancelled as a cascade effect.

**Finding the failing job:**

1. List jobs for the failed run:
   ```
   gh api repos/{owner}/{repo}/actions/runs/{run_id}/jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, conclusion, html_url}'
   ```
   If no `failure` conclusion, check for `startup_failure` or `timed_out` as well.

2. Get the failed job's logs:
   ```
   gh run view {run_id} --log-failed
   ```
   Logs are large — pipe through `grep -i 'error\|failed\|exit code' | head -50` to find the root cause quickly.

3. If `--log-failed` returns nothing (can happen when the failure is infrastructure-level), download full logs:
   ```
   gh run view {run_id} --log | grep -B5 -A5 'exit code [1-9]'
   ```

**Why everything else was cancelled:** GitHub Actions cancels all remaining jobs in a workflow run when a required job fails. The cancelled jobs did NOT fail on their own — they never ran (or were killed mid-run) because the failing job was either:
- A direct dependency via `needs:` — downstream jobs can't start
- Part of a matrix where `fail-fast: true` (default) kills sibling jobs
- In the same `concurrency` group, causing the run to abort

**Action:** Fix only the root-cause job's failure. Do not investigate cancelled jobs — they will pass once the root cause is resolved.

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
Add reusable **Codebase Patterns** to the TOP of progress.txt.

## Stop Condition

If ALL stories pass: <promise>COMPLETE</promise>
