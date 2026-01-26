# Performance Validation Examples

## Example 1: Index Addition

**Claim:** "Adding index on `user_id` improves query performance"

### Find existing queries
```bash
rg "WHERE.*user_id" --type sql
rg "findMany.*user_id" --type ts
```

### Before benchmark
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 'abc123';
-- Seq Scan on orders  (cost=0.00..2541.00 rows=1 width=156)
-- (actual time=12.4..45.2ms)
```

```bash
hyperfine --warmup 3 --runs 20 \
  'psql -c "SELECT * FROM orders WHERE user_id = '\''abc123'\''"'
# Mean: 47.3 ms +/- 4.2 ms
```

### After benchmark
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 'abc123';
-- Index Scan using idx_orders_user_id  (cost=0.42..8.44 rows=1 width=156)
-- (actual time=0.03..0.04ms)
```

```bash
hyperfine --warmup 3 --runs 20 \
  'psql -c "SELECT * FROM orders WHERE user_id = '\''abc123'\''"'
# Mean: 2.1 ms +/- 0.3 ms
```

### Result
**95% improvement** - Index eliminates sequential scan entirely.

---

## Example 2: API Endpoint Optimization

**Claim:** "Batching database calls reduces endpoint latency"

### K6 load test script
```javascript
// bench.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  iterations: 100,
  vus: 10,
};

export default function () {
  const res = http.get('http://localhost:3000/api/dashboard');
  check(res, { 'status is 200': (r) => r.status === 200 });
}
```

### Run benchmark
```bash
k6 run bench.js
```

### Before
```
avg=245ms, p95=312ms, p99=450ms
```

### After
```
avg=89ms, p95=112ms, p99=145ms
```

### Result
**64% improvement** in average latency due to reduced database round-trips.

---

## Example 3: Marginal/No Improvement (Honest Report)

**Claim:** "Adding composite index improves join performance"

### PR Comment

```markdown
## Performance Validation

### Test Environment
- 150K orders, 50K users
- Local PostgreSQL with warm cache

### BEFORE
Execution: 12.4 ms (Index Scan on users + Nested Loop)
Benchmark: Mean 14.2 ms +/- 3.1 ms

### AFTER
Execution: 11.8 ms (Index Scan using composite)
Benchmark: Mean 13.8 ms +/- 2.9 ms

### Result
- Improvement: **Marginal (~3%)**
- Statistical confidence: Variance ranges overlap significantly
- Reason: Original query already used efficient index path;
  composite index provides minimal benefit for this access pattern.
  May show more benefit at higher concurrency or with cold cache.
```

This demonstrates **honest reporting** when results don't match claims.

---

## Example 4: Query Optimization with EXPLAIN Analysis

**Claim:** "Rewriting subquery as JOIN improves performance"

### Before (subquery)
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM products
WHERE category_id IN (
  SELECT id FROM categories WHERE active = true
);

-- Planning Time: 0.15 ms
-- Execution Time: 156.23 ms
-- Buffers: shared hit=1234, read=567
```

### After (JOIN)
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT p.* FROM products p
INNER JOIN categories c ON p.category_id = c.id
WHERE c.active = true;

-- Planning Time: 0.18 ms
-- Execution Time: 23.45 ms
-- Buffers: shared hit=890, read=123
```

### Benchmark comparison
```bash
hyperfine --warmup 5 --runs 30 \
  'psql -f before.sql' \
  'psql -f after.sql'

# Benchmark 1 (before): Mean 162.3 ms +/- 12.1 ms
# Benchmark 2 (after):  Mean 28.7 ms +/- 3.2 ms
```

### Result
**85% improvement** - JOIN allows query planner to use more efficient hash join strategy instead of nested loop with subquery materialization.
