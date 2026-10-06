# Roadmap sync

This is an interactive session. It compares the technical roadmap in Notion with the sprint
data of the GitHub Projects linked from it, reports the mismatches, and updates Notion dates
only after the user approves each change. After each phase, present the result and wait for
the user, who may ask questions, change the analysis or approve a subset of the updates.

## Context

- Roadmap database: `https://www.notion.so/blackbirdhq/2fddf464a7e080969561fd84d4ecf951?v=2fddf464a7e0800da1f7000c81366342`
- Database ID: `2fddf464a7e080969561fd84d4ecf951`, read and written through the Notion MCP
  server
- Dashboard source: `~/projects/pm/roadmap-dashboard/`, which visualizes the same data. Read
  it for the data model; never modify it.
- State directory: `~/projects/pm/.state/roadmap-sync/`

## Notion database schema

| Property | Type | Description |
|----------|------|-------------|
| `Component` | Title | Project or initiative name |
| `Status` | Status | "In progress", "Planned", "Backlog", "Parking Lot", "Blocked" |
| `Category` | Select | Product, Cost, Performance/Scalability, Innovation/Capabilities, DevX/Tooling, Quality/Reliability, Tech debt, Code |
| `Priority` | Select | Priority level |
| `Estimate` | Select | Effort or complexity estimate |
| `Start date` | Date | Project start date |
| `End date` | Date | Project end date |
| `Resources` | People | Assigned developers |
| `Lead` | People | Team lead (first person) |
| `Product roadmap component` | Relation | Product milestone pages |
| `Sub-item` | Relation | Sub-item pages (phases) |
| `Parent item` | Relation | Non-empty when this page is a sub-item |
| `Issue specification` | Rich text or URL | Links to issue specs |
| `GitHub Project` | URL | e.g. `https://github.com/orgs/Org/projects/42` |

Sub-item pages carry `Component` (fallback `Name`), `Start date` (fallback `Date`),
`End date` and `Resources`. A sub-item with "hypercare" in its name, case-insensitive, is a
post-launch monitoring phase that may extend past the parent's end date.

Product milestone pages carry `Product Release Date`, `Commercial release date` and
`Component`.

## Phase 1: load the roadmap

1. Read `progress.txt` in the state directory for earlier runs and learnings.
2. Query the roadmap database for all items. For each, extract component, status, category,
   start and end dates, `GitHub Project` URL, sub-items with their own title, dates and
   resources, resources and lead, whether it is itself a sub-item, and the release dates of
   its linked product milestones.
3. Store the result in `roadmap-snapshot.json`:
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
         "resource_ids": ["person-id-1"],
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
           }
         ]
       }
     ]
   }
   ```

## Phase 2: fetch sprint data

For each item with a `GitHub Project` URL (`/orgs/{owner}/projects/{number}` or
`/users/{owner}/projects/{number}`):

4. Query the Projects v2 GraphQL API with `gh api graphql`, not `gh project item-list`:
   - every `ProjectV2IterationField` with both `configuration.iterations` and
     `configuration.completedIterations`;
   - all project items, 100 per page, to find which iterations they reference.
   Keep only referenced iterations. A sprint ends at `startDate + duration` days.
5. Store `projects/<owner>-<number>.json`:
   ```json
   {
     "fetched_at": "<ISO>",
     "owner": "Org",
     "number": 42,
     "sprints": [{"name": "Sprint 1", "start_date": "2026-01-15", "end_date": "2026-01-29"}],
     "earliest_start": "2026-01-15",
     "latest_end": "2026-04-09"
   }
   ```

## Phase 3: find problems

6. Compare each linked item against its sprints. Problem types:

   | Type | Condition |
   |------|-----------|
   | `end_date_too_early` | Notion end date is before the latest sprint end |
   | `end_date_too_late` | Notion end date is more than 28 days after the latest sprint end |
   | `start_date_mismatch` | Notion start date differs from the earliest sprint start by more than 7 days |
   | `sprint_start_drift` | A sprint starts on a day other than Monday; the fix is the preceding Monday, made in the GitHub iteration settings, not in Notion |
   | `milestone_exceeded` | Item end date is after its product release date |
   | `sub_item_gap` | Sub-item dates are not contiguous, each phase starting the day after the previous ends |
   | `sub_item_outside_parent` | Sub-item dates fall outside the parent's range |
   | `sub_item_missing_dates` | Sub-item has no start or end date |
   | `parent_child_start_mismatch` | First sub-item start differs from the parent start |
   | `parent_child_end_mismatch` | Last non-hypercare sub-item end differs from the parent end |
   | `no_github_project` | Item has no `GitHub Project` URL |
   | `empty_project` | Linked project references no sprints |

   Sprint coverage, matching the dashboard: a gap of 0 to 14 days between the latest sprint
   end and the Notion end date is `ok`, 14 to 28 days is `warning`, over 28 days is `behind`.
   For `behind`, suggest the latest sprint end plus a buffer. When parent dates move,
   sub-items may need proportional adjustment.

   Confidence: `high` when the sprint dates clearly bound the work, `medium` when the gap is
   14 to 28 days, `low` when sprints are few or missing. The project data carries no issue
   counts or completion state, so confidence rests on dates alone.

7. Write `report.json`:
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
             "problems": [{"type": "sub_item_outside_parent", "description": "...", "current_value": "2026-05-15", "suggested_value": "2026-04-30"}]
           }
         ]
       }
     ],
     "summary": {"total_items_checked": 5, "items_with_problems": 3, "total_problems": 7}
   }
   ```

## Phase 4: report and ask

8. Show the report:
   ```
   # Roadmap sync report

   ## <Initiative name>
   Status: <status> | Category: <category>
   GitHub Project: <url>
   Sprints: <earliest start> to <latest end> (<N> sprints)
   Sprint coverage: OK / Warning / Behind

   Problems:
   - End date too early: Notion says 2026-03-15, last sprint ends 2026-04-09
     Suggested: 2026-04-09
   - Sprint "Sprint 5" starts on Wednesday 2026-03-04 (should be Monday 2026-03-02)
     Fix in: GitHub Project iteration settings

   ## Items OK
   - <Initiative name>: dates aligned, sprint coverage OK
   ```
9. List each Notion update you propose, with page, field, old value and new value, and wait
   for the user's approval.

## Phase 5: apply approved updates

10. Update only what the user approved: `Start date` and `End date` on items and sub-items,
    keeping sub-item dates contiguous and leaving hypercare dates unchanged unless approved.
11. Re-fetch the changed pages and confirm the new values.
12. Append to `progress.txt`:
    ```
    ## <date> - Roadmap sync
    - Items checked: <N>
    - Problems found: <N>
    - Updates applied: <list>
    - Learnings: <patterns, gotchas>
    ---
    ```
