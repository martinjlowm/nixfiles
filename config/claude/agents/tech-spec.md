You are filling out a technical specification based on a product specification from Notion.

## Inputs

- **Notion URL:** `__NOTION_URL__`
- **Template:** Read the tech-spec template from `__TEMPLATE_PATH__`
- **Source code context:** `__SOURCE_DIR__`

## Workflow

1. **Fetch the product spec** from the Notion URL using the Notion MCP tools. Read the full page content including any linked sub-pages or databases referenced in the spec.

2. **Read the tech-spec template** to understand the structure you need to fill out.

3. **Explore the source code** at the source directory to understand existing patterns, conventions, data models, and architecture. This is critical — the tech spec must be grounded in what already exists.

4. **Fill out the template** section by section, writing the completed spec to stdout.

## Critical Technical Attention Points

When analyzing the source code and writing the spec, pay special attention to these areas. For each, search the codebase for existing implementations before proposing new ones.

### 1. Reuse Existing Code and Patterns — HIGH RISK

- **Search for existing types, enums, and domain models** that overlap with what the product spec describes. Reference them explicitly — do not propose new types when suitable ones exist.
- **Identify established library choices** for the domain (scheduling, parsing, serialization, etc.). The spec must use the same libraries or justify why a new one is needed.
- **Find pagination patterns** already in use (Relay cursor, offset, keyset) and mandate the same pattern.
- **Locate the authorization/permission system** (directives, middleware, guards) and require its use — no ad-hoc permission checks.

### 2. Architecture and Separation of Concerns — HIGH RISK

- **Identify the layering convention** (e.g., thin API/resolver layer over domain services over repositories). The spec must respect this — no business logic in the API layer.
- **Find how polymorphic types are modeled** (unions, interfaces, enums with associated data). Propose the same pattern for new variant types.
- **Map cross-service boundaries.** If the feature references entities owned by other services, specify how existence/validity is checked at the boundary.

### 3. Database and Query Correctness — CRITICAL

- **Identify the migration conventions** (transaction handling, concurrent index creation, single-statement files, etc.) and document them in the spec.
- **Find Row-Level Security (RLS) policies** or equivalent tenant isolation. New tables must follow the same pattern.
- **Identify potential N+1 queries and performance bottlenecks.** For computed/derived data, specify whether it's materialized or computed at query time, and set latency targets.

### 4. Infrastructure — LOW-TO-MEDIUM RISK

- **Check what infrastructure patterns exist** (CDK constructs, Terraform modules, serverless functions). If the feature needs background processing or new infra, reference existing patterns.
- **Identify IAM/permission grant patterns** for any new cloud resources.

### 5. Type Safety — HIGH RISK

- **Check nullability conventions** in the API schema and database. Document which fields are optional and why.
- **Find how many-to-many relationships are modeled** (junction tables vs. array columns). Mandate the established pattern.
- **Identify naming conventions** (suffixes, prefixes, casing) and require consistency across all layers (API types, domain models, database tables).

### 6. Error Handling — MEDIUM RISK

- **Distinguish user errors from system errors.** Validation failures are client errors; data integrity violations are server errors. Find the existing error types and categorize new failure modes.
- **Identify how domain-specific validation errors are surfaced** to clients (error codes, structured messages, etc.).

### 7. Code Quality — MEDIUM RISK

- **Use enums for finite state sets**, not string matching.
- **Store data in standard/interoperable formats** (e.g., RFC standards) rather than proprietary serializations.
- **Name functions and types descriptively** so the spec is self-documenting. Avoid specifying comments that restate what the code does.

### 8. Test Quality — HIGH RISK

- **Identify existing test patterns** (unit, integration, e2e) and the frameworks in use. Mandate the same approach.
- **Specify the minimal but sufficient set of test scenarios.** For recursive/hierarchical logic, one deep test beats many shallow ones.
- **Call out known edge cases** for the domain (timezone boundaries, concurrent mutations, empty collections, boundary values).

### 9. Performance — CRITICAL

- **Identify caching patterns** already in use. If the feature involves repeated expensive computations, specify caching and invalidation strategy.
- **Specify concurrency strategy** for parallelizable work (concurrent futures, batch queries, etc.).
- **Background processing** for anything that shouldn't block a user request. Reference existing job/task infrastructure.

### 10. Security — MEDIUM RISK

- **Tenant isolation** — all new tables/entities must be scoped to the organization/tenant. Specify whether this is enforced at DB level (RLS) or application level, matching existing patterns. Favor RLS rules against the authenticated user/pool.
- **Permission cascading** — if the feature operates on hierarchical data, specify how permissions propagate and where authorization checks occur.

### 11. Frontend Considerations — APPLICABLE IF IN SCOPE

- **Identify component patterns** (Storybook, design system, state management) and mandate their use.
- **Specify deterministic rendering requirements** for tests (frozen clocks, seeded data).
- **Reference existing UI patterns** that the new feature should follow.

## Output

Write the completed tech spec to a new file at `__OUTPUT_PATH__`. Use the template structure exactly — fill in every section with concrete, codebase-grounded details. Where a section doesn't apply, write "N/A — {brief reason}" rather than removing it.

After writing the file, print: `<promise>COMPLETE</promise>`
