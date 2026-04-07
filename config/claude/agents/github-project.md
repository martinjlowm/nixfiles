You are creating a GitHub project from a technical breakdown, copying the view-setup from an existing project to preserve sprint check-in views.

## Inputs

- **Tech spec:** `__SPEC_FILE__`
- **Source project (copy views from):** `__SOURCE_PROJECT_URL__`
- **Estimation baseline:** Read the estimation instructions from `__ESTIMATION_TEMPLATE__`
- **Source code context:** `__SOURCE_DIR__`

## Workflow

### Step 1: Read inputs

1. Read the tech spec at `__SPEC_FILE__` to understand the scope of work.
2. Read the estimation baseline at `__ESTIMATION_TEMPLATE__` to understand the complexity scale, capacity model, and scheduling procedure.
3. Explore the source code at `__SOURCE_DIR__` enough to validate the spec's scope and understand the repository structure.

### Step 2: Estimate and plan sprints

Follow the estimation procedure from the baseline document:

1. **Decompose** the tech spec into discrete issues. Each issue should correspond to one PR or a tightly-coupled cluster of PRs.
2. **Classify** each issue with points (1/2/3/5), code-size bucket (XS/S/M/L/XL), and dependencies.
3. **Schedule** issues into sprints using the capacity model and dependency order.

Each issue must be written as a typical PRD task with:
- A clear title
- Description of what needs to be implemented
- **Success criteria** — concrete, verifiable conditions that determine when the story is done:
  - Functional criteria specific to the task
  - Type checks pass
  - Tests pass
  - Code conventions are followed
  - Changes are concise and incremental

### Step 3: Copy the GitHub project

Copy the source project to preserve its view-setup (board views, sprint iteration fields, status fields, etc.):

```bash
# Get the source project ID
gh project view <source-number> --owner <source-owner> --format json --jq '.id'

# Copy the project
gh project copy <source-number> --source-owner <source-owner> --title "<new-project-title>" --drafts --format json
```

The new project title should reflect the tech spec's subject (e.g., "Feature: <spec title>").

Record the new project number for subsequent steps.

### Step 4: Configure sprint iterations

Set up sprint iterations on the new project matching the schedule from Step 2:

1. List the project fields to find the iteration field:
   ```bash
   gh project field-list <new-project-number> --owner <owner> --format json
   ```
2. Identify the iteration/sprint field (typically named "Sprint" or "Iteration").
3. Create iteration entries for each sprint in the schedule. Use the GraphQL API if needed:
   ```bash
   gh api graphql -f query='
   mutation {
     updateProjectV2IterationField(input: {
       projectId: "<project-node-id>",
       fieldId: "<iteration-field-id>",
       iterationId: "<iteration-id>",
       title: "Sprint N",
       startDate: "YYYY-MM-DD",
       duration: 14
     }) { projectV2IterationField { id } }
   }'
   ```

### Step 5: Create issues and add to the project

For each issue from the sprint plan:

1. Create the issue in the appropriate repository:
   ```bash
   gh issue create --repo <owner>/<repo> \
     --title "<issue-title>" \
     --body "$(cat <<'EOF'
   ## Description

   <what needs to be implemented>

   ## Success Criteria

   - [ ] <functional criterion 1>
   - [ ] <functional criterion 2>
   - [ ] Type checks pass
   - [ ] Tests pass
   - [ ] Code conventions are followed
   - [ ] Changes are concise and incremental

   ## Estimation

   - **Points:** <N>
   - **Code size:** <XS/S/M/L/XL>
   - **Dependencies:** <list or "None">

   ---
   *Created from tech spec: <spec-file-name>*
   EOF
   )"
   ```

2. Add the issue to the project:
   ```bash
   gh project item-add <new-project-number> --owner <owner> --url <issue-url> --format json
   ```

3. Set the sprint/iteration field on the project item:
   ```bash
   gh project item-edit --project-id <project-node-id> --id <item-id> --field-id <iteration-field-id> --iteration-id <sprint-iteration-id>
   ```

4. Set the status to the initial state (e.g., "Todo" or the first column).

### Step 6: Output summary

Print the estimation summary (following the format from the estimation baseline) and the new project URL.

After completing all steps, print: `<promise>COMPLETE</promise>`

## Important notes

- **Preserve view-setup:** The `gh project copy` command copies views, fields, and configuration from the source project. This is critical for sprint check-ins — do not create projects from scratch.
- **Issue ordering:** Create issues in dependency order so that later issues can reference earlier ones.
- **Sprint boundaries:** Each sprint is 2 weeks. Respect capacity limits from the estimation baseline.
- **Repository detection:** Create issues in the repository at `__SOURCE_DIR__` (use `git remote get-url origin` to determine the owner/repo).
