You are filling out a technical specification based on a product specification from Notion.

## Inputs

- Notion URL: `__NOTION_URL__`
- Template: read the tech-spec template from `__TEMPLATE_PATH__`
- Source code context: `__SOURCE_DIR__`

## Workflow

1. Fetch the product spec from the Notion URL using the Notion MCP tools. Read the full page, including any linked sub-pages or databases the spec references.

2. Read the tech-spec template to learn the structure you need to fill out.

3. Explore the source code at the source directory to learn the existing patterns, conventions, data models, and architecture. The tech spec must be grounded in what already exists, so don't skip this.

4. Fill out the template section by section, writing the completed spec to stdout.

## Critical technical attention points

When analyzing the source code and writing the spec, pay particular attention to these areas. For each, search the codebase for existing implementations before proposing new ones.

### 1. Reuse existing code and patterns (high risk)

- Search for existing types, enums, and domain models that overlap with what the product spec describes. Reference them explicitly. Do not propose new types when suitable ones exist.
- Identify the established library choices for the domain: scheduling, parsing, serialization. The spec must use the same libraries or justify why a new one is needed.
- Find the pagination pattern already in use (Relay cursor, offset, keyset) and mandate the same one.
- Locate the authorization and permission system (directives, middleware, guards) and require its use. No ad-hoc permission checks.

### 2. Architecture and separation of concerns (high risk)

- Identify the layering convention, such as a thin API/resolver layer over domain services over repositories. The spec must respect it. No business logic in the API layer.
- Find how polymorphic types are modeled (unions, interfaces, enums with associated data) and propose the same pattern for new variant types.
- Map cross-service boundaries. If the feature references entities owned by other services, specify how existence and validity get checked at the boundary.

### 3. Database and query correctness (critical)

- Identify the migration conventions (transaction handling, concurrent index creation, single-statement files) and document them in the spec.
- Find the Row-Level Security policies, or the equivalent tenant isolation. New tables must follow the same pattern.
- Identify potential N+1 queries and performance bottlenecks. For computed or derived data, specify whether it is materialized or computed at query time, and set latency targets.

### 4. Infrastructure (low to medium risk)

- Check which infrastructure patterns exist (CDK constructs, Terraform modules, serverless functions). If the feature needs background processing or new infra, reference the existing patterns.
- Identify the IAM grant patterns for any new cloud resources.

### 5. Type safety (high risk)

- Check the nullability conventions in the API schema and database. Document which fields are optional and why.
- Find how many-to-many relationships are modeled, junction tables or array columns, and mandate the established pattern.
- Identify the naming conventions (suffixes, prefixes, casing) and require consistency across every layer: API types, domain models, database tables.

### 6. Error handling (medium risk)

- Distinguish user errors from system errors. Validation failures are client errors, data integrity violations are server errors. Find the existing error types and categorize new failure modes.
- Identify how domain-specific validation errors reach clients: error codes, structured messages.

### 7. Code quality (medium risk)

- Use enums for finite state sets, not string matching.
- Store data in standard, interoperable formats such as RFC standards, rather than proprietary serializations.
- Name functions and types descriptively so the spec documents itself. Avoid specifying comments that restate what the code does.

### 8. Test quality (high risk)

- Identify the existing test patterns (unit, integration, e2e) and the frameworks in use. Mandate the same approach.
- Specify the minimal but sufficient set of test scenarios. For recursive or hierarchical logic, one deep test beats many shallow ones.
- Call out the known edge cases for the domain: timezone boundaries, concurrent mutations, empty collections, boundary values.

### 9. Performance (critical)

- Identify the caching patterns already in use. If the feature involves repeated expensive computations, specify the caching and invalidation strategy.
- Specify the concurrency strategy for parallelizable work: concurrent futures, batch queries.
- Use background processing for anything that shouldn't block a user request. Reference the existing job and task infrastructure.

### 10. Security (medium risk)

- Tenant isolation. All new tables and entities must be scoped to the organization or tenant. Specify whether that is enforced at the DB level through RLS or at the application level, matching existing patterns. Favor RLS rules against the authenticated user and pool.
- Permission cascading. If the feature operates on hierarchical data, specify how permissions propagate and where authorization checks happen.

### 11. Frontend considerations (if in scope)

- Identify the component patterns (Storybook, design system, state management) and mandate their use.
- Specify the deterministic rendering requirements for tests: frozen clocks, seeded data.
- Reference the existing UI patterns the new feature should follow.

## Output

Write the completed tech spec to a new file at `__OUTPUT_PATH__`. Use the template structure exactly and fill every section with concrete, codebase-grounded detail. Where a section doesn't apply, write "N/A, {brief reason}" rather than removing it.

After writing the file, print: `<promise>COMPLETE</promise>`
