# Project Estimation Guide

Estimate delivery timelines for technical specifications using historical
throughput data. The baseline was measured over a 6-month window (177 completed
items across 4 GitHub projects in a TypeScript + Rust monorepo). All numbers
were validated by recomputing statistics from per-item raw data.

---

## 1 — Complexity Scale

Each issue maps to a point estimate and code-size bucket. Cycle time is calendar
days from sprint start to issue close (2-week sprints = 14 calendar days).

| Complexity | Points | Code Size | Median Cycle | P90 Cycle | Typical Scope |
|------------|--------|-----------|--------------|-----------|---------------|
| Trivial | 1 | XS–S (≤150 lines) | 8.5 days | 16.6 days | Config tweak, small resolver, rename, one-file fix |
| Small | 2 | S–M (50–400 lines) | 13.4 days | 20.9 days | New field + tests, permission guard, UI component change |
| Medium | 3 | M–L (150–1000 lines) | 9.5 days | 15.9 days | End-to-end feature slice, migration + resolver + tests |
| Large | 5 | L–XL (400+ lines) | 16.7 days | 19.7 days | Multi-service feature, full CRUD + UI, complex rework |

### Code Size Reference

| Bucket | Lines Changed | Median Cycle | P90 Cycle |
|--------|---------------|--------------|-----------|
| XS (1–50) | ≤50 | 6.7 days | 9.7 days |
| S (51–150) | 51–150 | 8.5 days | 14.8 days |
| M (151–400) | 151–400 | 9.6 days | 20.9 days |
| L (401–1000) | 401–1000 | 13.5 days | 16.8 days |
| XL (1000+) | >1000 | 11.6 days | 21.7 days |

Use both tables as a cross-check. If you estimate 1pt but the implementation
looks like 400+ lines, it's probably a 2pt or 3pt item.

---

## 2 — Developer Capacity by Seniority

Throughput is measured **per developer per 2-week sprint**. Seniority is
classified by observed throughput and complexity range.

### Seniority Definitions

| Seniority | Items/Sprint | Points/Sprint | Median Cycle | Complexity Range |
|-----------|--------------|---------------|--------------|------------------|
| **Senior** | 3.8–5.3 | 6–12 | 9–11 days | All levels (1–5pt), leads critical path |
| **Mid-level** | 2.2–3.5 | 4–6 | 5–13 days | Mostly 1–3pt, some 5pt with guidance |
| **Junior** | 1.0–1.5 | 2–3 | 4–8 days | Primarily 1–2pt, shorter cycles on small scope |

#### Senior Developer Profile
- Sustains 3.8–5.3 items/sprint across all complexity levels
- Handles 5-point items independently (median 16.7d cycle)
- Dominates throughput on projects (observed: 64% of items on one project)
- Bottleneck risk: projects with a single senior cap at ~5.3 items/sprint
- Adding a second senior raises capacity to ~8 items/sprint (not 10.6 — coordination overhead)

#### Mid-level Developer Profile
- Steady 2.2–3.5 items/sprint, predominantly 1–3pt items
- Shorter cycle times on small items (5–7d) but longer on complex work (13d)
- Can sustain parallel work alongside seniors without significant coordination cost
- Typically handles 2–3pt items with full autonomy, needs direction on 5pt

#### Junior Developer Profile
- 1.0–1.5 items/sprint, mostly trivial/small items
- Low cycle times (4–8d) because scope is constrained
- Onboarding overhead inflates initial cycle times by ~50%
- Primarily contributes to 1pt items; 2pt with pairing/review support

### Observed Team Configurations

These are actual configurations from the baseline, anonymized:

**Backend-heavy project (75 items, 5 developers):**
- 2 seniors (80% of items): 3.8 + 2.9 items/sprint
- 2 juniors (part-time): 1.4 + 1.2 items/sprint
- 1 occasional contributor: ~2 items in 1 sprint
- Sprint average: 2.2 active devs, 5.8 items/sprint, 10.0 points/sprint
- Bug ratio: 0%

**Frontend-heavy project (99 items, 5 developers + 1 bot):**
- 1 senior (64% of items): 5.3 items/sprint
- 2 mid-levels: 2.2 + 3.0 items/sprint
- 2 juniors/occasional: 1.0–3.5 items/sprint (limited sprints)
- Sprint average: 2.3 active devs, 8.5 items/sprint
- Bug ratio: 14.1%

### Cross-Configuration Averages

| Metric | Backend Project | Frontend Project | Blended |
|--------|-----------------|------------------|---------|
| Active devs/sprint | 2.2 | 2.3 | 2.3 |
| Items/dev/sprint | 2.6 | 3.8 | ~3.0 |
| Points/dev/sprint | 4.4 | N/A | ~4.4 |

---

## 3 — Estimation Procedure

### Step 1 — Decompose into issues

Break the spec into discrete deliverables. Each issue should correspond to one
PR or a tightly-coupled cluster of PRs. If an issue feels larger than 5 points,
split it.

### Step 2 — Classify each issue

For every issue, assign:

1. **Points** (1 / 2 / 3 / 5) — use the complexity scale in Section 1.
2. **Code-size bucket** (XS / S / M / L / XL) — estimate from implementation
   details. Cross-check against the point value.
3. **Dependencies** — list issues that must complete before this one can start.

### Step 3 — Compute team capacity

```
senior_capacity     = count_seniors × 4.5    (items/sprint, conservative)
midlevel_capacity   = count_midlevels × 2.8  (items/sprint)
junior_capacity     = count_juniors × 1.2    (items/sprint)
total_items_sprint  = senior_capacity + midlevel_capacity + junior_capacity
```

For point-based capacity:
```
senior_points       = count_seniors × 8      (points/sprint, midpoint of 6–12)
midlevel_points     = count_midlevels × 5    (points/sprint)
junior_points       = count_juniors × 2.5    (points/sprint)
total_points_sprint = senior_points + midlevel_points + junior_points
```

**Scaling is sub-linear.** Each additional developer beyond 2 adds ~80%
marginal throughput due to coordination overhead. Apply a 0.8× discount
per developer after the second:

```
if total_devs > 2:
  excess = total_devs - 2
  total_items_sprint = first_two_capacity + (excess_capacity × 0.8)
```

### Step 4 — Account for overhead

Reserve capacity for non-feature work. The overhead percentage depends on
project type:

| Overhead | Backend-Only | Frontend-Heavy |
|----------|-------------|----------------|
| Bug fixes (reactive) | 0–5% | 14% |
| CI / DX toil | 5% | 5% |
| Review & carry-over | 5% | 5% |
| **Total reserved** | **10–15%** | **~24%** |

The 14% bug ratio was observed on a UI-heavy, user-facing project. Backend-only
projects had 0% bugs in the measurement window. Adjust based on your project's
frontend-to-backend ratio.

```
usable_capacity = total_points_sprint × (1 - overhead_pct)
```

### Step 5 — Assign complexity to seniority

Not all developers can handle all complexity levels:

| Issue Complexity | Who Can Take It |
|-----------------|-----------------|
| 1pt (Trivial) | Anyone |
| 2pt (Small) | Mid-level or Senior |
| 3pt (Medium) | Mid-level (with review) or Senior |
| 5pt (Large) | Senior only |

When scheduling, ensure 5pt items are assigned to senior capacity. Juniors
should not be allocated items above 2pt.

### Step 6 — Schedule into sprints

1. Sort issues by dependency order (topological sort).
2. For each sprint, fill up to `usable_capacity` with available issues
   whose dependencies are satisfied.
3. Respect seniority constraints from Step 5.
4. Items in the same sprint run in parallel (within the team).
5. Dependent chains define the critical path.

### Step 7 — Produce the estimate

```
total_sprints   = number of sprints needed to schedule all issues
timeline_weeks  = total_sprints × 2
buffered_weeks  = timeline_weeks × 1.2   (20% buffer for unknowns)
```

---

## 4 — Worked Example: 1 Senior + 2 Juniors

**Team composition:**
- 1 Senior developer (full-time on project)
- 2 Junior developers (full-time on project)

### Capacity Calculation

```
Senior:  1 × 4.5 items/sprint = 4.5 items,   1 × 8 pts  = 8 points
Juniors: 2 × 1.2 items/sprint = 2.4 items,   2 × 2.5 pts = 5 points
                                 ─────                      ──────
Raw total:                       6.9 items/sprint           13 points/sprint

Scaling (3 devs > 2): 1 excess dev at 80% → discount 1 junior by 20%
Adjusted: 4.5 + 1.2 + (1.2 × 0.8) = 6.66 items/sprint
          8   + 2.5 + (2.5 × 0.8) = 12.5 points/sprint

Overhead (assume mixed project, 20%):
Usable: 12.5 × 0.80 = 10.0 points/sprint
```

### Complexity Constraints

The senior is the only person who can handle 5pt and is preferred for 3pt work.
This creates a **senior bottleneck**: the critical path is governed by the
senior's 8 points/sprint (usable: 6.4 after overhead), not the team's 12.5.

For a hypothetical 40-point spec with this breakdown:

| Complexity | Count | Points Each | Total Points | Assignable To |
|------------|-------|-------------|--------------|---------------|
| 5pt | 2 | 5 | 10 | Senior only |
| 3pt | 4 | 3 | 12 | Senior (preferred) |
| 2pt | 4 | 2 | 8 | Senior or Mid (juniors need pairing) |
| 1pt | 5 | 1 | 5 | Anyone |

**Sprint plan:**

| Sprint | Senior (6.4 usable pts) | Junior A (2 usable pts) | Junior B (2 usable pts) | Total |
|--------|------------------------|------------------------|------------------------|-------|
| 1 | 5pt item (5) + 1pt (1) | 1pt (1) + 1pt (1) | 1pt (1) + 1pt (1) | 10 pts |
| 2 | 5pt item (5) | 2pt (2) | 2pt (2) | 9 pts |
| 3 | 3pt (3) + 3pt (3) | 2pt (2) | 2pt (2) | 10 pts |
| 4 | 3pt (3) + 3pt (3) | — | — | 6 pts |

(Assumes no dependencies between items. Dependencies extend the timeline.)

### Timeline

| Scenario | Sprints | Weeks | Calendar (from start) |
|----------|---------|-------|-----------------------|
| Optimistic (no deps, median cycles) | 4 | 8 | 2 months |
| Expected (with 20% buffer) | 5 | 10 | 2.5 months |
| Pessimistic (P90 cycles, senior bottleneck) | 6 | 12 | 3 months |

---

## 5 — Output Format

When presenting an estimate, use this structure:

```markdown
## Estimate: <Spec Title>

**Team:** <N> senior + <N> mid-level + <N> junior developers
**Usable capacity:** <X> points/sprint (after <N>% overhead)
**Senior capacity:** <X> points/sprint (bottleneck limit)
**Total scope:** <N> issues, <X> points

### Issue Breakdown

| # | Issue | Points | Size | Depends On | Assigned To | Sprint |
|---|-------|--------|------|------------|-------------|--------|
| 1 | ... | 2 | S | — | Junior | 1 |
| 2 | ... | 5 | XL | #1 | Senior | 2 |

### Critical Path

<sequence of dependent issues, noting which require senior capacity>

### Timeline

| Scenario | Sprints | Weeks | Calendar |
|----------|---------|-------|----------|
| Optimistic (median) | N | N×2 | ... |
| Expected (with buffer) | N | N×2×1.2 | ... |
| Pessimistic (P90) | N | N×2 | ... |
```

---

## 6 — Calibration Notes

These patterns from the baseline should inform judgment calls:

- **3-point items complete faster than 2-point items** (median 9.5d vs 13.4d).
  This is real — experienced engineers self-select into well-scoped complex
  work. Don't assume 3pt always takes longer than 2pt in scheduling.

- **XL code changes don't proportionally increase cycle time** over L changes
  (XL median 11.6d vs L median 13.5d). Review/integration overhead plateaus.
  The real cost is in lead time (XL median 37d vs L median 22d — these items
  sit in backlog longer).

- **Sprint spikes are not sustainable velocity.** Peak sprints of 21 and 19
  items were observed and correlate with batch-closing of sub-tasks. Use the
  median sprint velocity, not the peak.

- **Single-senior projects are throughput-capped.** A dominant contributor
  handling 64% of items caps the project at ~5.3 items/sprint. Adding a second
  senior would raise capacity to ~8 items/sprint, not 10.6.

- **Bug ratio depends on project type.** UI-heavy projects: 14% of sprint
  capacity goes to bugs. Backend-only projects: 0% observed. Adjust the
  overhead reserve accordingly.

- **Junior developers have lower variance, not just lower throughput.** Their
  median cycle times (4–8d) are shorter than seniors (9–11d) because their
  scope is constrained. But they cannot absorb complex work — if all remaining
  items are 3–5pt, juniors are effectively idle.

- **Negative cycle times exist** (7 items in baseline). These occur when items
  are closed before their assigned sprint starts — usually pre-work or sprint
  reclassification. Exclude these when computing capacity for new estimates.

---

## 7 — When to Distrust This Baseline

- **Novel technology or domain**: The baseline reflects TypeScript GraphQL +
  React + Rust work in a monorepo. For unfamiliar stacks or greenfield
  infrastructure, use a 1.5× buffer instead of 1.2×.

- **Team composition change**: Losing a senior or onboarding multiple juniors
  simultaneously costs 1–2 sprints of reduced throughput.

- **Scope creep**: This baseline measures issue-level cycle time, not
  specification-level. If the spec grows after estimation, re-run Step 6.

- **Baseline age**: Generated March 2026. Re-validate against fresh data every
  6 months. Fresh pulls show item counts can shift +10–60% after the fact due to
  retroactive sprint assignments and status changes in GitHub Projects.

---

## 8 — Quick Reference Card

For rapid estimation without full procedure:

| Team | Usable pts/sprint | Items/sprint | 20pt spec | 40pt spec |
|------|-------------------|--------------|-----------|-----------|
| 1 Senior | 6.4 | 3.6 | 4 sprints (8 wks) | 7 sprints (14 wks) |
| 1 Senior + 1 Mid | 10.4 | 5.8 | 2 sprints (4 wks) | 4 sprints (8 wks) |
| 1 Senior + 2 Juniors | 10.0 | 5.3 | 2 sprints (4 wks) | 4 sprints (8 wks) |
| 2 Seniors | 12.8 | 7.2 | 2 sprints (4 wks) | 4 sprints (8 wks) |
| 2 Seniors + 1 Mid | 16.0 | 9.0 | 2 sprints (4 wks) | 3 sprints (6 wks) |
| 1 Senior + 2 Mids | 14.0 | 7.8 | 2 sprints (4 wks) | 3 sprints (6 wks) |

**Important:** These assume uniform complexity distribution. If most points are
in 5pt items, the senior becomes the bottleneck regardless of team size. Always
check the critical path.

Buffered timeline = table value × 1.2. P90 pessimistic = table value × 1.5.
