# Spec loop

Each run of this prompt is one iteration. It delivers or revises one story from the spec
`__SPEC__` as one pull request, then ends. The state lives on disk under `./.state/__SPEC__/`
and survives between iterations. Nothing else survives.

## State

| File | Holds |
| --- | --- |
| `./specs/__SPEC__.md` | The spec, edited by the user while the loop runs |
| `./.state/__SPEC__/prd.json` | Stories with `acceptanceCriteria` and `passes`, derived from the spec |
| `./.state/__SPEC__/progress.txt` | Codebase patterns at the top, then one entry per iteration |
| `./.state/__SPEC__/review-state.json` | Per PR: comment ids already handled |
| `./.state/__SPEC__/deferred-prs.json` | Branches pushed without a PR because of the PR limit |

Story pass/fail state lives only in `passes` in `prd.json`.

## Workflow

1. Read `prd.json` and `progress.txt`, codebase patterns first.
2. Review every open PR of this spec, including stories with `passes: true`. List them with
   `gh pr list --state open --author @me --search "head:__SPEC__/"`. For each one:
   - Read every review thread and comment newer than `review-state.json` records. Handle
     each per the review-thread rules. Code changed for a review gets a test, or the
     commit message says why none is possible.
   - Fix failing or cancelled checks per "CI triage". Warnings are not failures.
   - If `gh pr view <pr> --json mergeable` is `CONFLICTING`, resolve the conflicts with
     `gh stack sync`, which rebases the stack onto the default branch.
   - Set `passes: false` while an unhandled comment, a failing check or a conflict remains.
3. Pick the highest-priority story with `passes: false` whose PR has no running checks.
   If `gh pr checks <pr> --json name,state` shows any `PENDING`, skip that story. If some
   checks already failed or were cancelled while others still run, fix that PR now. If
   every candidate is blocked on running checks, end the iteration.
4. Branch with `gh stack`. A new story becomes the next layer on top of the spec's stack:
   `gh stack add __SPEC__/<story-id>`. If a story touches a different module and shares no
   files with any existing layer, start its own stack with `gh stack init`. In a bare
   repository, first create the worktree with the `worktree` command in `PATH`. Never use
   `git worktree` or the `EnterWorktree` tool for it.
5. Enter the Nix dev shell before any work. It installs the pre-commit hooks.
6. Implement or revise that one story. Check every item in `acceptanceCriteria` against the
   code you wrote. Run typecheck and tests for the affected projects.
   If the story changes what renders in a browser:
   - Run the `visual-comparison` skill with the base branch as X and the story branch as Y.
   - Move `.visual-comparison/` to `./.state/__SPEC__/visual-comparison/<story-id>/`. Never
     commit it.
   - Investigate any pixel difference the story did not intend.
7. If the story claims a performance gain, benchmark before and after on production-sized
   data: 100K+ rows, several iterations, and `EXPLAIN (ANALYZE, BUFFERS)` for queries. Give
   the numbers and method in the PR body.
8. Commit as `<feat|fix|chore>(<component>): <story-id> - <title>`. The component is the
   project, or `*` for several.
9. Push with `gh stack submit --auto`, never with `--open`, so new PRs are drafts. Then set
   each new or changed PR's title and body with the `pr-description` skill. Respect the
   PR limit.
10. Mark `passes: true` only when all hold, checked one story at a time:
    - every check on the PR passed (none running, failed or cancelled);
    - `mergeable` is `MERGEABLE`;
    - every acceptance criterion is met by the code in the PR;
    - `git status` is clean;
    - `prd.json` requirements did not change since this iteration started.
11. Append to `progress.txt` in the format below. Write learnings there and nowhere else,
    never into the repository's AGENTS.md, CLAUDE.md or other shared files.
12. Re-read `progress.txt`, `prd.json` and the spec. If any changed during the iteration,
    act on the change before ending.

Handle one story per iteration and end after step 12. Check CI once per PR and never wait
for it. If a check is still running, move on or end the iteration.

## Stack upkeep

- Keep the stack within a week of the default branch. Find the oldest default-branch commit
  missing from the bottom layer with
  `git log --format=%ci --reverse <bottom>..origin/master | head -1`. If it is older than
  7 days, run `gh stack sync`.
- Fix a problem in the layer that introduced it, then `gh stack rebase --upstack`. If a review
  comment on a higher PR concerns code from a lower layer, fix it in the lower layer.
- After adding a layer or syncing, validate the top branch:
  - migrations apply in order, with no duplicate timestamps or conflicting schema changes;
  - typecheck and lint pass;
  - tests pass.

  A failure that also exists on the default branch is not this stack's to fix. Never push a
  top branch that fails validation.

## PR limit

At most 2 open PRs per spec. At the limit, push the branch with
`git push -u origin <branch>`, not `gh stack submit`, which would open a PR for it. Record
the branch in `deferred-prs.json` as `{"branch", "pushed_at", "reason": "PR limit reached"}`.
When existing PRs merge or close, open the deferred PRs, oldest first.

## Progress format

```
## <date> - <story-id>
- What was implemented
- Files changed
- Learnings: patterns, gotchas
---
```

`progress.txt` holds implementation notes and learnings only: no CI status, no story status
summaries, no plans for the next iteration. Add reusable codebase patterns at the top.

## Stop condition

If all stories pass: `<promise>COMPLETE</promise>`
