# Agent instructions

You have access to a Notion MCP server. Use it to read and update the technical roadmap database.

## Context

- Roadmap database: `https://www.notion.so/blackbirdhq/2fddf464a7e080969561fd84d4ecf951?v=2fddf464a7e0800da1f7000c81366342`
- Database ID: `2fddf464a7e080969561fd84d4ecf951`
- Dashboard source: `~/projects/pm/roadmap-dashboard/`, the project dashboard that visualizes this data. Do NOT modify files in this directory, but read it to understand the data model
- State directory: `~/projects/pm/.state/roadmap-sync/`

## Notion database schema

The roadmap database uses these Notion property names and types:

| Property | Type | Description |
|----------|------|-------------|
| `Component` | Title | Project or initiative name |
| `Status` | Status | Item status: "In progress", "Planned", "Backlog", "Parking Lot", "Blocked" |
| `Category` | Select | Work category. One of Product, Cost, Performance/Scalability, Innovation/Capabilities, DevX/Tooling, Quality/Reliability, Tech debt, Code |
| `Priority` | Select | Priority level |
| `Estimate` | Select | Effort or complexity estimate |
| `Start date` | Date | Project start date |
| `End date` | Date | Project end date |
| `Resources` | People | Assigned developers (array of person IDs) |
| `Lead` | People | Team lead (first person extracted) |
| `Product roadmap component` | Relation | Links to product milestone pages |
| `Sub-item` | Relation | Links to sub-item pages (phases) |
| `Parent item` | Relation | Indicates this page is a sub-item of another |
| `Issue specification` | Rich text or URL | Links to issue specs |
| `GitHub Project` | URL | Direct URL property linking to a GitHub Project, e.g. `https://github.com/orgs/Org/projects/42` |

### Sub-item pages

Sub-items are separate Notion pages linked via the `Sub-item` relation. Each has:
- `Component` (Title), or `Name` as a fallback, for the phase name
- `Start date` (Date), or `Date` as a fallback, for the phase start
- `End date` (Date) for the phase end
- `Resources` (People) for the developers assigned to this phase

Hypercare detection. Sub-items with "hypercare" in the name, case-insensitive, get special handling. They represent a post-launch monitoring phase and the dashboard draws them as a separate overlay bar.

### Product milestone pages

Linked via `Product roadmap component` relation. Each has:
- `Product Release Date` (Date)
- `Commercial release date` (Date)
- `Component` (Title)

## GitHub sprint data model

The dashboard fetches sprint and iteration data from GitHub Projects v2 through the GraphQL API, NOT the `gh project item-list` CLI command. The data model is:

```typescript
interface SprintData {
  name: string;      // Iteration title (e.g., "Sprint 1")
  startDate: string; // ISO date YYYY-MM-DD
  endDate: string;   // Computed: startDate + duration days
}

interface SprintSummary {
  earliestStart: string | null; // First sprint's start date
  latestEnd: string | null;     // Last sprint's end date
  sprints: SprintData[];        // All referenced sprints, sorted by startDate
}
```

Key details:
- Sprint end date is `startDate + duration`, where duration comes in days from the iteration field
- Only iterations actually referenced by project items are included
- It considers both active (`configuration.iterations`) and completed (`configuration.completedIterations`) iterations
- The dashboard does NOT track per-sprint issue counts, open/closed status, or completion flags
- GitHub project URLs parse as `/orgs/{owner}/projects/{number}` or `/users/{owner}/projects/{number}`

### Dashboard sprint visualization

The dashboard overlays sprint coverage on roadmap bars with three states:
- `sprint-ok`: sprints cover the item or end before the item's end date
- `sprint-warning`: up to a 14-day gap between last sprint end and item end date
- `sprint-behind`: more than a 14-day gap between last sprint end and item end date

## Workflow

### Phase 1: load the roadmap

1. Read `~/projects/pm/.state/roadmap-sync/progress.txt` for previously handled items and learnings
2. Query the Notion roadmap database (`2fddf464a7e080969561fd84d4ecf951`) to fetch all roadmap items. Extract for each item:
   - Component (title)
   - Status
   - Category
   - Start date, End date
   - GitHub Project URL (the `GitHub Project` URL property)
   - Sub-items via the `Sub-item` relation, each with their own title, start date, end date, and resources
   - Product roadmap component IDs (for milestone dates)
   - Resources and Lead
   - Whether the item is itself a sub-item (`Parent item` relation is non-empty)
3. For items with `Product roadmap component` relations, fetch the linked pages to get milestone release dates
4. Store the fetched state in `~/projects/pm/.state/roadmap-sync/roadmap-snapshot.json`:
   ```json
   {
     "fetched_at": "<ISO>",
     "items": [
       {
         "notion_id": "<page-id>",
         "title": "Initiative name",
         "status": "In progress",
         "category": "Product",
         "start_date": "2026-01-15",
         "end_date": "2026-04-30",
         "github_project_url": "https://github.com/orgs/Org/projects/42",
         "github_project_owner": "Org",
         "github_project_number": 42,
         "is_sub_item": false,
         "resource_ids": ["person-id-1", "person-id-2"],
         "team_lead_id": "person-id-1",
         "milestone": {
           "product_release_date": "2026-04-15",
           "commercial_release_date": "2026-05-01",
           "product_component_name": "Feature X"
         },
         "sub_items": [
           {
             "notion_id": "<page-id>",
             "title": "Initiative - Phase 1",
             "start_date": "2026-01-15",
             "end_date": "2026-02-28",
             "resource_ids": ["person-id-1"],
             "is_hypercare": false
           },
           {
             "notion_id": "<page-id>",
             "title": "Initiative - Hypercare",
             "start_date": "2026-04-15",
             "end_date": "2026-04-30",
             "resource_ids": ["person-id-2"],
             "is_hypercare": true
           }
         ]
       }
     ]
   }
   ```

### Phase 2: fetch GitHub project sprint data

For each roadmap item that has a `GitHub Project` URL:

5. Use `gh api graphql` to fetch sprint and iteration data from the GitHub Projects v2 API. The query must:
   - Fetch all `ProjectV2IterationField` fields and their configuration (both `iterations` and `completedIterations`)
   - Paginate through all project items (100 per page) to find which iterations are referenced
   - Compute sprint end dates as `startDate + duration` days
   - Only include iterations that are actually referenced by at least one project item
6. Identify the **earliest sprint start** and **latest sprint end** across all referenced sprints
7. Store per-project sprint data in `~/projects/pm/.state/roadmap-sync/projects/<owner>-<number>.json`:
   ```json
   {
     "fetched_at": "<ISO>",
     "owner": "Org",
     "number": 42,
     "sprints": [
       {
         "name": "Sprint 1",
         "start_date": "2026-01-15",
         "end_date": "2026-01-29"
       }
     ],
     "earliest_start": "2026-01-15",
     "latest_end": "2026-04-09"
   }
   ```

### Phase 3: compare and identify problems

8. For each roadmap item with a linked GitHub project, compare the Notion dates against the GitHub sprint data. Check for:

   Parent item date alignment:
   - `start_date` should match or precede the earliest sprint start date
   - `end_date` should match or follow the latest sprint end date
   - Flag if the Notion end date is earlier than the last sprint's end date (`end_date_too_early`)
   - Flag if the Notion end date is more than 28 days, two sprint durations, after the last sprint end (`end_date_too_late`, a stale estimate)
   - Flag if the Notion start date diverges from the earliest sprint start by more than 7 days (`start_date_mismatch`)

   Sprint coverage assessment, mirroring the dashboard visualization:
   - A gap of 0 to 14 days between the latest sprint end and the Notion end date is OK
   - A gap of 14 to 28 days is a warning
   - A gap over 28 days is behind. Suggest adjusting the end date to the latest sprint end plus a buffer

   Sprint start day drift:
   - All sprints must start on a Monday. Check each sprint's `startDate` day-of-week
   - Flag any sprint that starts on a non-Monday day (`sprint_start_drift`)
   - The suggested fix is the nearest preceding Monday (move the start date back to the Monday of that week)
   - This is a GitHub Project configuration problem. Report it, but do not try to fix it through Notion. Include it in the report so the user can correct the iteration settings in GitHub

   Sub-item (phase) alignment:
   - Sub-items represent phases where resources are potentially allocated
   - Sub-item date ranges should be contiguous, each phase starting the day after the previous one ends
   - No sub-item should have dates outside the parent's start to end range
   - The first sub-item's start date should match the parent's start date
   - The last non-hypercare sub-item's end date should match the parent's end date. Hypercare sub-items may extend past it
   - If the parent dates are adjusted, sub-items may need proportional adjustment

   Milestone alignment:
   - If a product release date exists, the item's end date should be on or before it
   - Flag if the item's end date exceeds the product release date

   General problems:
   - Roadmap items with no linked GitHub project, where sprints can't be validated
   - Roadmap items whose linked project returns no referenced sprints, meaning it is empty or misconfigured

9. Compile all findings into a structured problems report stored at `~/projects/pm/.state/roadmap-sync/report.json`:
    ```json
    {
      "generated_at": "<ISO>",
      "items": [
        {
          "notion_id": "<page-id>",
          "title": "Initiative name",
          "sprint_coverage": "ok | warning | behind",
          "problems": [
            {
              "type": "end_date_too_early",
              "description": "Notion end date (2026-03-15) is before the last sprint ends (2026-04-09)",
              "current_value": "2026-03-15",
              "suggested_value": "2026-04-09",
              "confidence": "high"
            }
          ],
          "sub_item_problems": [
            {
              "notion_id": "<sub-item-page-id>",
              "title": "Initiative - Phase 2",
              "problems": [
                {
                  "type": "sub_item_outside_parent",
                  "description": "Sub-item end date (2026-05-15) exceeds parent end date (2026-04-30)",
                  "current_value": "2026-05-15",
                  "suggested_value": "2026-04-30"
                }
              ]
            }
          ]
        }
      ],
      "summary": {
        "total_items_checked": 5,
        "items_with_problems": 3,
        "total_problems": 7
      }
    }
    ```

### Phase 4: present the summary for approval

10. Output the summary to the user as a readable report:

    ```
    # Roadmap sync report

    ## <Initiative Name>
    Status: <status> | Category: <category>
    GitHub Project: <url>
    Sprints: <earliest start> to <latest end> (<N> sprints)
    Sprint coverage: OK / Warning / Behind

    Problems:
    - End date too early: Notion says 2026-03-15, last sprint ends 2026-04-09
      Suggested: 2026-04-09
    - Sub-item "Phase 2" ends after parent (2026-05-15 > 2026-04-30)
      Suggested: adjust to 2026-04-30
    - Sprint "Sprint 5" starts on Wednesday 2026-03-04 (should be Monday 2026-03-02)
      Fix in: GitHub Project iteration settings

    ## Items OK
    - <Initiative Name>: dates aligned, sprint coverage OK
    ```

11. **Stop and wait for user approval** before making any changes. List the specific Notion updates you intend to make:
    - Which pages get updated
    - Which date fields change, with the old and new value

    Ask the user to confirm before proceeding to Phase 5.

### Phase 5: apply updates

**Only execute this phase if the user has approved the changes.**

12. For each approved change, update the Notion page using the MCP server:
    - Update `Start date` and/or `End date` on parent roadmap items
    - Update `Start date` and/or `End date` on sub-item pages
    - Maintain contiguity of sub-item dates when adjusting
    - Preserve hypercare sub-item dates unless explicitly approved for change

13. After all updates, re-fetch the roadmap items to verify the changes landed correctly

14. Log results in `~/projects/pm/.state/roadmap-sync/progress.txt`

## Confidence levels

The dashboard's GitHub integration only provides sprint date ranges, not per-sprint issue counts or completion status:

- `high`: all sprint dates are well-defined and the latest sprint end clearly bounds the work
- `medium`: sprint data exists but the gap between the latest sprint end and the Notion end date is ambiguous, 14 to 28 days
- `low`: few sprints defined, or the sprint data is sparse or missing

## Problem types

| Type | Description |
|------|-------------|
| `end_date_too_early` | Notion end date is before the latest sprint end date |
| `end_date_too_late` | Notion end date is more than 28 days after the latest sprint end, a stale estimate |
| `start_date_mismatch` | Notion start date diverges from the earliest sprint start by more than 7 days |
| `no_github_project` | Roadmap item has no `GitHub Project` URL |
| `empty_project` | Linked GitHub project returns no referenced sprints |
| `milestone_exceeded` | Item end date exceeds its product release date |
| `sub_item_gap` | Non-contiguous sub-item dates |
| `sub_item_outside_parent` | Sub-item dates fall outside parent range |
| `sub_item_missing_dates` | Sub-item has no start or end date |
| `parent_child_start_mismatch` | First sub-item start does not match the parent start |
| `parent_child_end_mismatch` | Last non-hypercare sub-item end does not match the parent end |
| `sprint_start_drift` | Sprint starts on a non-Monday day |

## Progress format

Append to `~/projects/pm/.state/roadmap-sync/progress.txt`:
```
## [Date] - Roadmap sync
- Items checked: [N]
- Problems found: [N]
- Updates applied: [list of changes]
- Learnings: [patterns, gotchas]
---
```

## Interactive session

This agent runs as an interactive session. After completing each phase, present the results and wait for user input before proceeding. The user may ask follow-up questions, request changes to the analysis, or selectively approve updates. Remain in the session and respond to the user's requests.
