# {Feature Name} - technical specification

**Product spec:** [{Feature Name} (Notion)]({notion-url})

## Table of contents

1. [Executive summary](#executive-summary)
2. [Critical requirements](#critical-requirements)
3. [Current state analysis](#current-state-analysis)
4. [Target architecture](#target-architecture)
5. [Data model](#data-model)
6. [Core concepts](#core-concepts)
7. [User stories and implementation plan](#user-stories-and-implementation-plan)
8. [Nice-to-have features](#nice-to-have-features)
9. [Migration strategy](#migration-strategy)
10. [Testing strategy](#testing-strategy)
11. [Risks and mitigations](#risks-and-mitigations)

---

## Executive summary

<!-- 2-4 sentences describing the high-level goal. Follow with a bullet list of
     the key capabilities this feature introduces. -->

- **Capability 1**: Brief description
- **Capability 2**: Brief description
- **Capability 3**: Brief description

### Implementation platform

<!-- Where in the codebase this work lands. Reference existing patterns. -->

**{Backend, frontend or both}** (`{path}`) using:
- {framework / library 1}
- {framework / library 2}
- Existing patterns from `{module}` modules

### Success criteria

<!-- Measurable outcomes that define "done". Include performance targets where applicable. -->

- {Criterion 1}
- {Criterion 2}
- Under {N}ms p95 latency for {critical query}, per page
- Pagination support for all list queries

---

## Critical requirements

<!-- Group requirements by theme. Use tables for scannable requirement lists. -->

### 1. {Requirement group}

| Requirement | Description |
|-------------|-------------|
| **{Name}** | {What it does and why} |
| **{Name}** | {What it does and why} |

### 2. {Requirement group}

| Requirement | Description |
|-------------|-------------|
| **{Name}** | {What it does and why} |
| **{Name}** | {What it does and why} |

### 3. API considerations

<!-- Naming conventions, versioning, backward compatibility, feature flags, pagination. -->

| Requirement | Description |
|-------------|-------------|
| **Naming** | {V2 suffix for conflicts, etc.} |
| **Transition period** | {Coexistence strategy with existing APIs} |
| **Feature flag** | {Flag name and scope: frontend-only, backend} |
| **Pagination** | {Connection, Edge and PageInfo pattern} |

---

## Feature flag

<!-- If applicable. Describe flag scope, defaults per environment, and rollout phases. -->

The `{FLAG_NAME}` feature flag guards the **{scope}**.

| Environment | Default | Notes |
|-------------|---------|-------|
| Development | `true` | Enabled for development |
| Staging | `true` | Enabled for testing |
| Production | `false` | Gradual rollout per organization |

### Rollout strategy

1. Phase 1: enable for internal test organizations
2. Phase 2: enable for beta customers, opt-in
3. Phase 3: enable for all new organizations
4. Phase 4: migrate existing, enable globally
5. Phase 5: remove the flag, deprecate the predecessor

---

## Current state analysis

### Existing systems

<!-- For each system being replaced or integrated, describe what exists today,
     what works, and what limits it. -->

#### 1. {System A}, legacy

**Location:** `/{path}/`

| Aspect | Current state | Limitation |
|--------|---------------|------------|
| {Aspect} | {Description} | {What's missing} |

#### 2. {System B}, reference

**Location:** `/{path}/`

| Aspect | Current state | Reusable |
|--------|---------------|----------|
| {Aspect} | {Description} | {Yes or no, and what to extract} |

---

## Target architecture

### System overview

<!-- ASCII diagram showing the major components and their relationships.
     Keep it high-level. Detail goes in the data model section. -->

```
┌─────────────────────────────────────────────────────────┐
│                    {SYSTEM NAME}                          │
│                    ({path})                               │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │                {Component A}                        │  │
│  │  • {Responsibility 1}                              │  │
│  │  • {Responsibility 2}                              │  │
│  └───────────────────────────────────────────────────┘  │
│                          │                                │
│                          ▼                                │
│  ┌───────────────────────────────────────────────────┐  │
│  │                {Component B}                        │  │
│  │  • {Responsibility 1}                              │  │
│  │  • {Responsibility 2}                              │  │
│  └───────────────────────────────────────────────────┘  │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### {Domain-specific flow}

<!-- If the feature involves hierarchical, sequential, or branching logic,
     illustrate with an ASCII tree or flow diagram. -->

```
{Flow diagram}
```

---

## Data model

### Entity relationship diagram

<!-- ASCII ER diagram showing entities, their fields, and relationships.
     Include types and cardinality. -->

```
┌───────────────────┐       ┌───────────────────┐
│     {Entity A}    │       │     {Entity B}    │
├───────────────────┤       ├───────────────────┤
│ id: UUID          │◄──────│ entityAId: UUID   │
│ organizationId    │       │ field: Type        │
│ name: String      │       │ ...               │
└───────────────────┘       └───────────────────┘
```

<!-- Note: Detailed PostgreSQL schemas and API type definitions should be
     specified in separate sub-specifications during implementation. -->

---

## Core concepts

<!-- Explain the 2-4 domain concepts that a reader must understand to follow the
     implementation plan. Use diagrams where they add clarity. -->

### {Concept 1}

{Explanation of how it works, resolution rules, edge cases.}

### {Concept 2}

{Explanation with example scenario or diagram.}

---

## User stories and implementation plan

<!-- Group user stories into Epics. Each story has:
     - A user story statement (As a ..., I want ..., so that ...)
     - Acceptance criteria (checkbox list)
     - Implementation steps table (Step | Component | Task) -->

### Epic 1: {Epic name}

#### US-{PREFIX}-1: {Story title}

**User story:**
As a **{Role}**, I want to {action} so that {benefit}.

**Acceptance criteria:**
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

**Implementation steps:**

| Step | Component | Task |
|------|-----------|------|
| 1.1 | Backend | {Task description} |
| 1.2 | Backend | {Task description} |
| 1.3 | Frontend | {Task description} |

#### US-{PREFIX}-2: {Story title}

**User story:**
As a **{Role}**, I want to {action} so that {benefit}.

**Acceptance criteria:**
- [ ] {Criterion 1}
- [ ] {Criterion 2}

**Implementation steps:**

| Step | Component | Task |
|------|-----------|------|
| 2.1 | Backend | {Task description} |
| 2.2 | Frontend | {Task description} |

---

### Epic 2: {Epic name}

<!-- Repeat the user story pattern for each epic. -->

---

## Nice-to-have features

<!-- Features explicitly out of MVP scope but worth documenting for future iterations. -->

- **{Feature}**: {Brief description}
- **{Feature}**: {Brief description}

---

## Migration strategy

### Phase overview

<!-- Timeline with phases. Each phase lists concrete deliverables. -->

```
Phase 1: {Name} (Weeks {N}-{M})
├── {Deliverable 1}
├── {Deliverable 2}
└── {Deliverable 3}

Phase 2: {Name} (Weeks {N}-{M})
├── {Deliverable 1}
├── {Deliverable 2}
└── {Deliverable 3}

Phase N: legacy phase-out (Weeks {N}-{M})
├── Dual-write period
├── Migration tooling
└── V1 deprecation and removal
```

---

## Testing strategy

### Unit tests

| Component | Test focus |
|-----------|-----------|
| {Component} | {What to verify} |

### Integration tests

| Scenario | Description |
|----------|-------------|
| {Scenario} | {What to verify end-to-end} |

### E2E tests

| Flow | Steps |
|------|-------|
| {Flow name} | {Step 1 -> Step 2 -> Verify} |

---

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| {Risk description} | High, medium or low | {How to address} |

---

## Appendix

<!-- Reference material: ID formats, enum summaries, entity comparison tables,
     or anything that supports the spec but doesn't belong in the main flow. -->

### A. {Reference topic}

{Content}

### B. {Reference topic}

| {Key} | {Value} |
|-------|---------|
| {Item} | {Description} |
