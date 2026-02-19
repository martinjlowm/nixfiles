# Loop Agent Instructions

## Your Task

1. Read `./.state/__SPEC__/prd.json` constructed from `./specs/__SPEC__.md`
2. Read `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
3. Worktree-/branch name: `[SPEC_SLUG]/[STORY]`
4. **CRITICAL: Review and address PR feedback** for all stories, even if `passes: true`:
  - Fetch all PR review comments using `gh pr view --comments` and `gh api`
  - Address **every** unresolved comment before proceeding
  - Rebase based on the base-branch (or origin/master if PR is merged)
  - If the PR is closed, continue as-is
  - Address any failing or cancelled GitHub Actions CI PR checks if relevant to
    the changes. Cancellations cascade from a failure that is rooted in the
    logs - look for error - warnings are not a reason for a failure
  - Mark the task incomplete (`passes: false`) if there are any unaddressed
    feedback or CI failures
  - See **PR Review Feedback Requirements** section below for details
5. Change context into the correct branch and its worktree
  - branched off of the dependent branch/worktree
  - if there is none, default branching off of origin/master
  - use the `worktree <worktree-name> --base <base-branch>` tool that is
    available in PATH to prepare the worktree (this may take a few minutes!)
6. Before doing any work in the worktree, enter the Nix dev shell to make sure
   you have the tooling you need
  - Pre-commit hooks are generated from this
7. Pick highest priority story where `passes: false` **and no CI checks are
   currently running** (see **CI Check Flow** below)
8. Implement, revisit or revise (see **Revising** below) that **ONE** story
9. Run typecheck and tests selectively in projects that should be affected
10. Update AGENTS.md files with learnings
11. Commit: `[feat|fix|chore]([Component]): [ID] - [Title]` and include a
    reference to the `<base-branch>` - if a pull request exists for the
    base-branch, use that instead. Component can be `*` to represent many
    components otherwise specific projects, e.g. ui-app, ms-graphql-devices
12. Push to origin (NEVER force push, but utilize upstream merging before
    pushing instead) and create a draft PR (see **PR Limit** below)
13. Revise the PR title and description summarizing the factual changes
14. **Do not mark `passes: true` yet** — CI checks must complete first (see
    **CI Check Flow**). Continue to the next story immediately.
15. Append learnings to progress.txt
16. On subsequent iterations, re-check CI for previously pushed stories and
    update prd.json: `passes: true` only when all checks have passed

## CI Check Flow

**Do not wait for CI checks after pushing.** After pushing and creating/updating
a PR, move on to the next story immediately. CI checks triggered by a push run
asynchronously — do not block on them.

### Selecting stories

When picking the next story to work on (step 7), **skip** any story whose PR has
CI checks currently in progress (`in_progress`, `queued`, or `pending` status).
Check with:

```bash
gh pr checks <pr_number> --json name,state,status
```

- If any check has `status: "in_progress"` or `status: "queued"`, skip that
  story and move to the next highest priority story with `passes: false`
- If all stories with `passes: false` have running CI, end the iteration
  normally — do not wait

### Marking stories as passing

A story may only be marked `passes: true` when CI checks have **all completed
successfully**. On a subsequent iteration, re-check CI status for stories that
were pushed but not yet marked passing:

1. Run `gh pr checks <pr_number>` to get final CI status
2. If all checks passed → mark `passes: true`
3. If any checks failed → investigate and fix (see **Revising** below)
4. If checks are still running → skip, pick another story

## Revising

**All CI checks must pass.** Determine if failing CI checks are relevant to the
story in question. If CI checks are cancelled it is because of a cascading
effect from a cancel-workflow action that cancels all other jobs. There will be
at least one check that fails. Grep for errors in the logs. The logs can contain
A LOT of data, so grepping is a must.

**The changes must represent the latest revised version of the story.** Any
changes that aren't relevant to fulfilling the success criteria must be
discarded.

## PR Limit

**Maximum 5 open PRs per spec.** The limit is scoped to the current spec being
implemented — PRs from other specs do not count. Before creating a new PR:

1. Check open PR count for this spec:
   `gh pr list --state open --author @me --search "head:__SPEC_SLUG__/" | wc -l`
   (where `__SPEC_SLUG__` is the spec's branch prefix, e.g. `my-feature`)
2. If 5 or more PRs are open for this spec:
   - **Still push the branch** to origin (`git push -u origin <branch>`)
   - **Do not create a PR** - document in progress.txt that branch is pushed but
     PR creation is deferred
   - Continue to the next story
3. When an existing PR for this spec is merged or closed, create PRs for pending
   branches

Track deferred PRs in `./.state/__SPEC__/deferred-prs.json`:
```json
{
  "deferred": [
    {"branch": "spec/story-6", "pushed_at": "2024-01-15T10:30:00Z", "reason": "PR limit reached (5 open for this spec)"}
  ]
}
```

## PR Review Feedback Requirements

**Addressing PR review comments is mandatory.** No story is complete until all
review feedback has been addressed.

### Fetching Review Comments

Use the GitHub CLI to fetch all review comments:

```bash
# Get PR review comments
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments

# Get PR reviews with their state
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews

# Get general PR comments (conversation)
gh pr view {pr_number} --comments
```

### Addressing Comments

1. **Review every comment** - Do not skip or ignore any feedback
2. **Resolve explicitly** - Either implement the requested change or reply with
   a clear explanation if you disagree (then implement anyway unless trivial)
3. **Track progress** - Update `./.state/__SPEC__/review-state.json` with:
   ```json
   {
     "pr_number": 123,
     "last_addressed_comment_id": "IC_abc123",
     "last_addressed_at": "2024-01-15T10:30:00Z",
     "addressed_comments": ["IC_abc123", "IC_def456"],
     "pending_comments": []
   }
   ```
4. **Re-check after push** - New comments may arrive; always fetch latest before
   marking complete

### Comment State Tracking

The `review-state.json` file MUST be updated after addressing each comment:
- `last_addressed_comment_id`: ID of the most recently addressed comment
- `last_addressed_at`: Timestamp when it was addressed
- `addressed_comments`: Array of all addressed comment IDs
- `pending_comments`: Array of comment IDs still requiring action

This allows resumption of work and prevents re-addressing the same comments.

### When to Mark Story Complete

A story can only have `passes: true` when:
- All review comments have been addressed
- `pending_comments` array is empty
- CI checks have **all completed successfully** (not just initiated) — if checks
  are still running, skip and revisit on a later iteration. Cancelled checks
  cascade from a failure in one specific check
- Changes have been pushed
- Ensure the PR title and description represents the changeset

## Performance Validation Requirements

When a task involves **performance claims** (e.g., "optimizes queries",
"improves latency", "adds indexes for performance"), rigorous validation is
REQUIRED:

### Discover Existing Query Patterns

Before benchmarking, locate existing queries and patterns in the repository:

1. **Find existing queries**:
   - Search for `.sql` files, migration directories, and embedded SQL
   - Look for ORM query patterns (Prisma, TypeORM, Drizzle, SQLx, etc.)
   - Check for GraphQL resolvers with database access
   - Identify API endpoints that perform database operations

2. **Locate existing test infrastructure**:
   - Search for performance tests, benchmarks, or load tests
   - Find seed data scripts or fixtures
   - Check for existing `EXPLAIN` usage in tests or documentation

3. **Reference repository patterns**:
   - Use existing query patterns as baseline for comparison
   - Follow established conventions for query construction
   - Leverage existing test utilities and database helpers

### Benchmarking Tools

Use appropriate benchmarking tools to evaluate results over multiple iterations:

- **K6**: For HTTP/API endpoint load testing and latency measurements
- **Hyperfine**: For CLI commands, scripts, or database query benchmarks
- **pgbench**: For PostgreSQL-specific workload testing
- **Existing tools**: Check the repository for established benchmarking setups

Always run multiple iterations to account for variance—single-run results are
not statistically meaningful.

### Before/After Report

1. **Test Environment**: Document realistic scale
   - Use production-representative data volume (100K+ rows, not 10K)
   - Include hierarchy depth and data distribution that matches real usage
   - Note: Local warm-cache testing may not reveal production benefits
   - Reference existing seed scripts or test fixtures from the repository

2. **BEFORE Benchmark** (without the change):
   - Run `EXPLAIN (ANALYZE, BUFFERS)` on affected queries
   - Document execution time, planning time, buffer hits
   - Capture the query plan (which indexes used, seq scans, etc.)
   - Use existing query patterns from the codebase as test cases
   - Run multiple iterations with benchmarking tools (e.g., `hyperfine`)

3. **AFTER Benchmark** (with the change):
   - Same queries with identical test data
   - Same EXPLAIN output format
   - Same number of iterations
   - Direct comparison

4. **Honest Assessment**:
   - Document what improved AND what didn't
   - Explain WHY the improvement occurs (or doesn't)
   - Note limitations of local testing vs production
   - Compare against any existing performance baselines in the repository
   - Include statistical summary (min, max, mean, std dev) from multi-run benchmarks

### Example PR Comment Format

```markdown
## Performance Validation

### Test Environment
- X rows in table Y
- Realistic data distribution: [describe]
- Seed script used: `path/to/seed.ts` (if applicable)
- Benchmarking tool: K6 / Hyperfine / pgbench

### Queries Tested
- Reference: `path/to/query.sql` or `path/to/resolver.ts:L42`
- Pattern: [describe the query pattern from the codebase]

### BEFORE (without change)
[Query plan output]
Execution: X.XX ms

Benchmark (N iterations):
  Mean: X.XX ms ± X.XX ms
  Min: X.XX ms, Max: X.XX ms

### AFTER (with change)
[Query plan output]
Execution: X.XX ms

Benchmark (N iterations):
  Mean: X.XX ms ± X.XX ms
  Min: X.XX ms, Max: X.XX ms

### Result
- Improvement: X% faster / Marginal / No change
- Statistical confidence: [describe variance overlap]
- Reason: [explain why]
```

## Progress Format

APPEND to progress.txt:

## [Date] - [Story ID]
- What was implemented
- Files changed
- **PR Review Feedback Addressed:**
  - [Comment ID]: [Summary of feedback and how it was addressed]
  - Last addressed: [comment ID] at [timestamp]
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
