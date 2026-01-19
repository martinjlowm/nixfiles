# Loop Agent Instructions

## Your Task

1. Read `./.state/__SPEC__/prd.json` constructed from `./specs/__SPEC__.md`
2. Read `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
3. Worktree-/branch name: `[SPEC_SLUG]/[STORY]`
4. Evaluate necessary change requests for all stories, even if `passes: true` and
  - address any pull request reviews from GitHub (use gh) and
    rebase based on the base-branch. If the PR is merged into master, rebase
    based on origin/master
  - address any failing GitHub Actions CI PR checks if relevant to
    the changes
  - mark the task incomplete (`passes: false`) if there are any feedback or CI
    failures to address
5. Change context into the correct branch and its worktree
  - branched off of the dependent branch/worktree
  - if there is none, default branching off of origin/master
  - use the `worktree <worktree-name> --base <base-branch>` tool that is
    available in PATH to prepare the worktree (this may take a few minutes!)
6. Before doing any work in the worktree, enter the Nix dev shell to make sure
   you have the tooling you need
  - Pre-commit hooks are generated from this
7. Pick highest priority story where `passes: false`
8. Implement that ONE story
9. Run typecheck and tests selectively in projects that should be affected
10. Update AGENTS.md files with learnings
11. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` and include a
    reference to the `<base-branch>` - if a pull request exists for the
    base-branch, use that instead. Component can be `*` to represent many
    components otherwise specific projects, e.g. ui-app, ms-graphql-devices
12. Update prd.json: `passes: true`
13. Append learnings to progress.txt
14. Push to origin and create a draft PR

## Progress Format

APPEND to progress.txt:

## [Date] - [Story ID]
- What was implemented
- Files changed
- **Learnings:**
  - Patterns discovered
  - Gotchas encountered
---

## Codebase Patterns

Add reusable patterns to the TOP of progress.txt:

## Codebase Patterns
- Migrations: Use IF NOT EXISTS
- React: useRef<Timeout | null>(null)

## Stop Condition

If ALL stories pass, reply: <promise>COMPLETE</promise>

Otherwise end normally.
