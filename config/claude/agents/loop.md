# Loop Agent Instructions

## Your Task

1. Read `./.state/__SPEC__/prd.json` constructed from `./specs/__SPEC__.md`
2. Read `./.state/__SPEC__/progress.txt` (check Codebase Patterns first)
3. Worktree-/branch name: `[SPEC_SLUG]/[STORY]`
4. Evaluate necessary change requests for all stories, even if `passes: true` and
  - address any pull request reviews from GitHub (use gh) and rebase based on
    the base-branch - even if progress.txt indicates it's complete. If the PR is
    merged into master, rebase based on origin/master
  - if the PR is closed, continue as-is
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
