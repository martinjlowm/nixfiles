# {Feature Name} - Technical Specification

**Product Spec:** [{Feature Name} (Notion)]({notion-url})

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Critical Requirements](#critical-requirements)
3. [Current State Analysis](#current-state-analysis)
4. [Target Architecture](#target-architecture)
5. [Data Model](#data-model)
6. [Core Concepts](#core-concepts)
7. [User Stories & Implementation Plan](#user-stories--implementation-plan)
8. [Nice-to-Have Features](#nice-to-have-features)
9. [Migration Strategy](#migration-strategy)
10. [Testing Strategy](#testing-strategy)
11. [Risks & Mitigations](#risks--mitigations)

---

## Executive Summary

<!-- 2-4 sentences describing the high-level goal. Follow with a bullet list of
     the key capabilities this feature introduces. -->

- **Capability 1**: Brief description
- **Capability 2**: Brief description
- **Capability 3**: Brief description

### Implementation Platform

<!-- Where in the codebase this work lands. Reference existing patterns. -->

**{Backend/Frontend/Both}** (`{path}`) using:
- {framework / library 1}
- {framework / library 2}
- Existing patterns from `{module}` modules

### Success Criteria

<!-- Measurable outcomes that define "done". Include performance targets where applicable. -->

- {Criterion 1}
- {Criterion 2}
- < {N}ms p95 latency for {critical query} (per page)
- Pagination support for all list queries

---

## Critical Requirements

<!-- Group requirements by theme. Use tables for scannable requirement lists. -->

### 1. {Requirement Group}

| Requirement | Description |
|-------------|-------------|
| **{Name}** | {What it does and why} |
| **{Name}** | {What it does and why} |

### 2. {Requirement Group}

| Requirement | Description |
|-------------|-------------|
| **{Name}** | {What it does and why} |
| **{Name}** | {What it does and why} |

### 3. API Considerations

<!-- Naming conventions, versioning, backward compatibility, feature flags, pagination. -->

| Requirement | Description |
|-------------|-------------|
| **Naming** | {V2 suffix for conflicts, etc.} |
| **Transition Period** | {Coexistence strategy with existing APIs} |
| **Feature Flag** | {Flag name and scope — frontend-only, backend, etc.} |
| **Pagination** | {Connection/Edge/PageInfo pattern} |

---

## Feature Flag

<!-- If applicable. Describe flag scope, defaults per environment, and rollout phases. -->

The `{FLAG_NAME}` feature flag guards the **{scope}**.

| Environment | Default | Notes |
|-------------|---------|-------|
| Development | `true` | Enabled for development |
| Staging | `true` | Enabled for testing |
| Production | `false` | Gradual rollout per organization |

### Rollout Strategy

1. **Phase 1**: Enable for internal test organizations
2. **Phase 2**: Enable for beta customers (opt-in)
3. **Phase 3**: Enable for all new organizations
4. **Phase 4**: Migrate existing, enable globally
5. **Phase 5**: Remove flag, deprecate predecessor

---

## Current State Analysis

### Existing Systems

<!-- For each system being replaced or integrated, describe what exists today,
     what works, and what limits it. -->

#### 1. {System A} (Legacy)

**Location:** `/{path}/`

| Aspect | Current State | Limitation |
|--------|---------------|------------|
| {Aspect} | {Description} | {What's missing} |

#### 2. {System B} (Reference)

**Location:** `/{path}/`

| Aspect | Current State | Reusable |
|--------|---------------|----------|
| {Aspect} | {Description} | {Yes/No — what to extract} |

---

## Target Architecture

### System Overview

<!-- ASCII diagram showing the major components and their relationships.
     Keep it high-level — detail goes in the Data Model section. -->

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

### {Domain-Specific Flow}

<!-- If the feature involves hierarchical, sequential, or branching logic,
     illustrate with an ASCII tree or flow diagram. -->

```
{Flow diagram}
```

---

## Data Model

### Entity Relationship Diagram

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

## Core Concepts

<!-- Explain the 2-4 domain concepts that a reader must understand to follow the
     implementation plan. Use diagrams where they add clarity. -->

### {Concept 1}

{Explanation of how it works, resolution rules, edge cases.}

### {Concept 2}

{Explanation with example scenario or diagram.}

---

## User Stories & Implementation Plan

<!-- Group user stories into Epics. Each story has:
     - A user story statement (As a ..., I want ..., so that ...)
     - Acceptance criteria (checkbox list)
     - Implementation steps table (Step | Component | Task) -->

### Epic 1: {Epic Name}

#### US-{PREFIX}-1: {Story Title}

**User Story:**
As a **{Role}**, I want to {action} so that {benefit}.

**Acceptance Criteria:**
- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

**Implementation Steps:**

| Step | Component | Task |
|------|-----------|------|
| 1.1 | Backend | {Task description} |
| 1.2 | Backend | {Task description} |
| 1.3 | Frontend | {Task description} |

#### US-{PREFIX}-2: {Story Title}

**User Story:**
As a **{Role}**, I want to {action} so that {benefit}.

**Acceptance Criteria:**
- [ ] {Criterion 1}
- [ ] {Criterion 2}

**Implementation Steps:**

| Step | Component | Task |
|------|-----------|------|
| 2.1 | Backend | {Task description} |
| 2.2 | Frontend | {Task description} |

---

### Epic 2: {Epic Name}

<!-- Repeat the user story pattern for each epic. -->

---

## Nice-to-Have Features

<!-- Features explicitly out of MVP scope but worth documenting for future iterations. -->

- **{Feature}**: {Brief description}
- **{Feature}**: {Brief description}

---

## Migration Strategy

### Phase Overview

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

Phase N: Legacy Phase-Out (Weeks {N}-{M})
├── Dual-write period
├── Migration tooling
└── V1 deprecation and removal
```

---

## Testing Strategy

### Unit Tests

| Component | Test Focus |
|-----------|-----------|
| {Component} | {What to verify} |

### Integration Tests

| Scenario | Description |
|----------|-------------|
| {Scenario} | {What to verify end-to-end} |

### E2E Tests

| Flow | Steps |
|------|-------|
| {Flow name} | {Step 1 -> Step 2 -> Verify} |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| {Risk description} | High/Medium/Low | {How to address} |

---

## Appendix

<!-- Reference material: ID formats, enum summaries, entity comparison tables,
     or anything that supports the spec but doesn't belong in the main flow. -->

### A. {Reference Topic}

{Content}

### B. {Reference Topic}

| {Key} | {Value} |
|-------|---------|
| {Item} | {Description} |
