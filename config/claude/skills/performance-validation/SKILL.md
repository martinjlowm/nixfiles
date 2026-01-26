---
name: performance-validation
description: Validates performance claims with benchmarks and statistical proof. Use when code changes claim to optimize queries, improve latency, add indexes for performance, or make any performance-related improvements.
argument-hint: "[optional: specific claim or file to validate]"
---

# Performance Validation

When code changes include **performance claims** (e.g., "optimizes queries", "improves latency", "adds indexes for performance"), rigorous validation is REQUIRED before the claim can be accepted.

## Process

### 1. Discover Existing Patterns

Before benchmarking, locate existing queries and patterns:

- Search for `.sql` files, migrations, embedded SQL, ORM patterns
- Find existing performance tests, benchmarks, or seed data scripts
- Check for existing `EXPLAIN` usage in tests or documentation
- Use existing query patterns as baseline for comparison

### 2. Select Benchmarking Tools

Use appropriate tools for **multiple iterations** (single-run results are not statistically meaningful):

| Tool | Use Case |
|------|----------|
| **K6** | HTTP/API endpoint load testing |
| **Hyperfine** | CLI commands, scripts, database queries |
| **pgbench** | PostgreSQL-specific workloads |

### 3. Document Test Environment

- Use production-representative data volume (100K+ rows, not 10K)
- Include realistic hierarchy depth and data distribution
- Note: Local warm-cache testing may not reveal production benefits
- Reference existing seed scripts or test fixtures

### 4. Run Before/After Benchmarks

**BEFORE** (without the change):
```bash
EXPLAIN (ANALYZE, BUFFERS) SELECT ...;
hyperfine --warmup 3 --runs 10 'psql -c "SELECT ..."'
```

**AFTER** (with the change):
- Same queries, identical test data, same iterations

### 5. Provide Honest Assessment

Document what improved AND what didn't, explain WHY, note testing limitations.

## PR Comment Template

```markdown
## Performance Validation

### Test Environment
- X rows in table Y
- Data distribution: [describe]
- Benchmarking tool: K6 / Hyperfine / pgbench

### Queries Tested
- Reference: `path/to/query.sql` or `path/to/resolver.ts:L42`

### BEFORE (without change)
[Query plan output]
Benchmark (N iterations): Mean X.XX ms +/- X.XX ms

### AFTER (with change)
[Query plan output]
Benchmark (N iterations): Mean X.XX ms +/- X.XX ms

### Result
- Improvement: X% faster / Marginal / No change
- Statistical confidence: [variance overlap?]
- Reason: [explain why]
```

## Additional Resources

- For detailed examples, see [examples.md](examples.md)
