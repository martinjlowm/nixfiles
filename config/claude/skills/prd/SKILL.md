---
name: prd
description: Create a technical breakdown PRD from a product initiative. Translates Notion product items into GitHub project epics/tasks, technical roadmap entries, and success criteria grounded in the reference codebase. Use when the user wants to plan a product initiative, create a technical PRD, or break down a Notion product item into engineering work.
version: 1.0.0
---

# Technical PRD

Translates a product initiative (typically linked from Notion) into a fully scoped technical breakdown with GitHub project tracking, Notion roadmap entries, and codebase-grounded success criteria.

## When to use

Use this skill when:
- The user provides a Notion link to a product item and wants a technical breakdown
- The user asks to create a PRD, technical plan, or engineering breakdown for a product initiative
- The user wants to set up a GitHub project with epics and tasks for a product initiative

## Inputs

The user must provide:

| Input | Required | Description |
|-------|----------|-------------|
| Notion product item URL | Yes | Link to the product item page containing scope, personas, and problem statements |
| Reference codebase | Yes | The repository to ground the technical breakdown in. Defaults to the current working directory |
| Developer resources | No | Number of developers allocated. Defaults to 1 |
| Baseline estimation file | No | Path to a file with complexity and estimation baselines for scoping tasks |
| Product ready date | No | The date after which engineering work can begin |

## Workflow

### Phase 1: gather product context

1. Fetch the Notion product item from the provided URL. Extract:
   - Scope definition
   - Target personas
   - Problem statements
   - Acceptance criteria, if any
   - The product ready date, if the page specifies one

2. Ask the user to clarify or confirm any ambiguous scope before proceeding.

### Phase 2: analyze the reference codebase

1. Explore the codebase to learn:
   - Architecture and module boundaries relevant to the initiative
   - Existing patterns, conventions, and abstractions that the work must follow
   - The test infrastructure: test frameworks, coverage tooling, CI pipeline
   - Code style and linting rules, from config files such as `.eslintrc`, `biome.json`, or `prettier`
   - The deployment and release workflow

2. Identify the impacted areas: which modules, services, or layers get touched.

3. Note the code conventions success criteria must enforce: naming, structure, error handling patterns.

### Phase 3: write the technical PRD

Produce a structured PRD document containing:

#### 3.1 Overview
- The product initiative summary, from Notion
- Link to the Notion product item
- Target personas and problem statements

#### 3.2 Technical scope
- Impacted modules and services, each with a brief rationale
- New components or abstractions needed
- Integration points: APIs, events, data stores
- Migration and data concerns, if any

#### 3.3 User stories and tasks
Break the scope into user stories. Each one must include:
- **Description.** What the user can do, and why
- **Technical tasks.** Concrete implementation steps grounded in the codebase
- **Complexity estimate.** Use the baseline estimation file if provided. Otherwise estimate in story points (1/2/3/5/8/13) assuming **1 developer**, or the specified resource count
- **Dependencies.** Which stories must be completed first

#### 3.4 Success criteria

Every user story MUST have success criteria that ensure:

1. The described behavior works end-to-end
2. Test suites pass, with unit, integration, and e2e tests written and green
3. CI checks pass, meaning a linked PR passes every CI pipeline check
4. Code conventions are followed, so the changes conform to repository lint rules, naming conventions, file structure patterns, and the architectural boundaries identified in Phase 2

Format success criteria as a checklist:
```
- [ ] User can [do the thing described in the story]
- [ ] Tests: [specific test file(s) or describe coverage] pass
- [ ] PR passes CI checks
- [ ] Code follows [specific convention from the repo]
```

#### 3.5 Phased epic breakdown, the MVP critical path

Organize user stories into **epics**, prioritized by MVP critical path in phases:

- **Phase 1, MVP Core.** The minimum set of epics for the feature to function at all
- **Phase 2, MVP Complete.** Epics that round out the MVP experience: edge cases, polish, secondary flows
- **Phase 3, Post-MVP.** Nice-to-haves, optimizations, extended functionality

Each epic lists its constituent user stories and tasks in dependency order.

#### 3.6 Estimation summary

| Epic | Stories | Total points | Estimated duration |
|------|---------|-------------|-------------------|
| ... | ... | ... | ... |

Estimate duration against the specified developer count, defaulting to 1. If a baseline estimation file is provided, reference it for per-story calibration.

Include a **total project duration** estimate from start to end of Phase 3.

### Phase 4: create the GitHub project

1. Copy the GitHub project template from `https://github.com/orgs/FactbirdHQ/projects/77` to preserve the existing view setup:

```bash
gh api graphql -f query='
  mutation($ownerId: ID!, $projectId: ID!, $title: String!) {
    copyProjectV2(input: {
      ownerId: $ownerId,
      projectId: $projectId,
      title: $title
    }) {
      projectV2 { url number id }
    }
  }
' -f ownerId="$(gh api graphql -f query='{ organization(login: "FactbirdHQ") { id } }' -q '.data.organization.id')" \
  -f projectId="$(gh api graphql -f query='{ organization(login: "FactbirdHQ") { projectV2(number: 77) { id } }  }' -q '.data.organization.projectV2.id')" \
  -f title="<PROJECT TITLE>"
```

2. Create epics as GitHub issues in the target repository, labeled appropriately, one per epic from the phased breakdown.

3. Create task issues for each user story and task, linked to their parent epic. Include:
   - Description from the PRD
   - Success criteria checklist
   - Complexity estimate label or field
   - A phase label: Phase 1, Phase 2, or Phase 3

4. Add all issues to the GitHub project and organize them in the board views.

### Phase 5: create the Notion roadmap entry

1. Create a technical roadmap item in the Notion database at:
   `https://www.notion.so/blackbirdhq/2fddf464a7e080969561fd84d4ecf951?v=2fddf464a7e0800da1f7000c81366342`

   The roadmap item must include:
   - Title: the initiative name
   - Reference: a link to the original Notion product item
   - Start date: a date **after** the product ready date
   - End date: calculated from the total project duration estimate, all phases including hypercare
   - A link to the GitHub project

2. Create a sub-item for each phase using the "Sub-item" field on the parent roadmap item. Each phase sub-item must include:
   - Title: `<Initiative Name> - <Phase Name>`, for example "Operator View - MVP Core"
   - Description: a summary of the scope this phase covers, which epics and stories it includes and what capability it delivers
   - Start date: sequenced after the previous phase. Phase 1 starts after the product ready date
   - End date: calculated from the phase's estimated duration

   The phases to create as sub-items are:
   - Phase 1, MVP Core
   - Phase 2, MVP Complete
   - Phase 3, Post-MVP
   - Hypercare, **2 weeks** as the initial baseline, starting immediately after Phase 3 ends

   The hypercare period is included in the end date calculation of the parent roadmap item.

3. Validate timeline alignment:
   - The parent roadmap item's start date MUST equal Phase 1's start date
   - The parent roadmap item's end date MUST equal the Hypercare end date
   - Sub-item dates must be contiguous, each phase starting the day after the previous phase ends
   - No sub-item may have dates outside the parent's start to end range
   - The sum of all sub-item durations must equal the parent item's total duration

### Phase 6: review with the user

Present the complete plan to the user for review:
- PRD summary
- GitHub project link
- Notion roadmap entry link
- Total timeline visualization with phase breakdown

Validate that:
- All phase sub-item dates are contiguous and fall within the parent roadmap item's range
- No phase exceeds its allocated duration
- The parent item's total timeline matches the sum of all phases

Ask for approval before finalizing. Adjust based on feedback.

## Estimation guidelines

When a baseline estimation file is provided:
- Load it and use its complexity benchmarks to calibrate story point estimates
- Reference specific entries from the baseline when justifying estimates
- Let the baseline set the sprint planning granularity

When no baseline file is provided:
- Use Fibonacci story points (1/2/3/5/8/13)
- Assume 1 developer unless explicitly specified otherwise
- Assume a rough velocity of 8 to 10 story points per two-week sprint

## CLI reference

### `gh project` commands

The `gh project` CLI uses `--owner` (NOT `--org`) to specify the organization:

```bash
# CORRECT
gh project item-list <number> --owner FactbirdHQ --limit 50 --format json

# WRONG, fails with "unknown flag: --org"
gh project item-list <number> --org FactbirdHQ
```

## Tips

- Always ground technical tasks in actual code paths. Reference specific files, modules, or patterns from the codebase
- If the Notion page lacks detail, ask the user rather than assuming scope
- Keep epics small enough to be completable within 1-2 sprints where possible
- The MVP critical path should be the shortest path to a demo-able feature
- Success criteria must be concrete and verifiable. Avoid vague statements like "works correctly"
- When creating GitHub issues, use the repository's existing label taxonomy where applicable
