---
name: prd
description: Turn a Notion product item into a codebase-grounded technical PRD, then a GitHub project and Notion roadmap entry once approved. Use to plan a product initiative or break it into engineering work.
---

# Technical PRD

Translate a product initiative into a scoped technical breakdown. The PRD is a draft until the
user approves it, and nothing is created in GitHub or Notion before then.

## Inputs

| Input | Required | Default |
|-------|----------|---------|
| Notion product item URL (scope, personas, problem statements) | Yes | |
| Reference codebase | Yes | the current working directory |
| Developer count | No | 1 |
| Baseline estimation file | No | Fibonacci points, 8 to 10 per two-week sprint |
| Product ready date | No | from the Notion page if it gives one |

## Phase 1: product context

Fetch the Notion item and extract the scope, personas, problem statements, acceptance criteria
and product ready date. Where the page is thin or ambiguous, ask the user rather than assume
scope.

## Phase 2: the codebase

Learn the architecture and module boundaries the initiative touches, the conventions and
abstractions the work must follow, the test and CI setup, the lint configuration, and the
release workflow. Name the impacted modules, services and layers, and every task later cites
real files, modules or patterns from this pass.

## Phase 3: write the PRD

1. **Overview:** the initiative summary, the Notion link, personas and problem statements.
2. **Technical scope:** impacted modules with a one-line rationale each, new components or
   abstractions, integration points (APIs, events, stores), migration and data concerns.
3. **User stories**, each with a description (what the user can do, and why), technical tasks
   grounded in the code, a complexity estimate, and dependencies. With a baseline file,
   calibrate against its entries and cite them; otherwise use Fibonacci points
   (1/2/3/5/8/13) for the given developer count.
4. **Success criteria** per story, concrete and checkable. Name the behaviour, the tests that
   cover it, and the repository convention it must follow; never "works correctly".

   ```
   - [ ] User can <do the thing the story describes>
   - [ ] Tests: <test files or coverage>
   - [ ] Follows <specific convention from the repo>
   ```

5. **Epics by MVP critical path**, each listing its stories in dependency order, sized to fit
   one or two sprints where possible:
   - **Phase 1, MVP Core:** the least that makes the feature work, the shortest path to a
     demo.
   - **Phase 2, MVP Complete:** edge cases, polish, secondary flows.
   - **Phase 3, Post-MVP:** nice-to-haves and optimisations.
6. **Estimation summary:** a table of epic, stories, points and duration for the developer
   count, and the total from start to the end of Phase 3.

## Phase 4: review with the user

Present the PRD, the planned GitHub issues and the planned roadmap dates as a draft. Adjust
until the user approves. Create nothing before that approval.

## Phase 5: the GitHub project

1. Copy the template project `https://github.com/orgs/FactbirdHQ/projects/77` to keep its
   views:

   ```bash
   gh api graphql -f query='
     mutation($ownerId: ID!, $projectId: ID!, $title: String!) {
       copyProjectV2(input: {ownerId: $ownerId, projectId: $projectId, title: $title}) {
         projectV2 { url number id }
       }
     }
   ' -f ownerId="$(gh api graphql -f query='{ organization(login: "FactbirdHQ") { id } }' -q '.data.organization.id')" \
     -f projectId="$(gh api graphql -f query='{ organization(login: "FactbirdHQ") { projectV2(number: 77) { id } } }' -q '.data.organization.projectV2.id')" \
     -f title="<PROJECT TITLE>"
   ```

2. File one issue per epic, and one per story or task linked to its epic, carrying its
   description, success-criteria checklist, estimate and phase. Set each issue's Type (`Task`
   by default, `Feature` for an epic of new functionality). Record the estimate and phase in
   the project's fields, not as labels, and add no labels or assignees.
3. Add every issue to the project. `gh project` takes `--owner FactbirdHQ`, not `--org`.

## Phase 6: the Notion roadmap entry

1. Create an item in the
   [technical roadmap](https://www.notion.so/blackbirdhq/2fddf464a7e080969561fd84d4ecf951?v=2fddf464a7e0800da1f7000c81366342)
   with the initiative name as title, a link to the product item, a link to the GitHub
   project, a start date after the product ready date, and an end date that includes
   hypercare.
2. Add a sub-item per phase through the "Sub-item" field, titled
   `<Initiative Name> - <Phase Name>`, with a description of the epics and capability it
   delivers and its dates: Phase 1, MVP Core; Phase 2, MVP Complete; Phase 3, Post-MVP; and
   Hypercare, two weeks starting right after Phase 3.
3. Check the timeline: the parent starts with Phase 1 and ends with Hypercare, each phase
   starts the day after the previous one ends, and no sub-item falls outside the parent.

Report the GitHub project link, the roadmap entry link, and the phase timeline.
