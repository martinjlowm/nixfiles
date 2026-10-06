---
name: visual-comparison
description: Compare two web app environments (X and Y) page by page for visual and functional parity and post screenshot pairs to the PR. Use for staging vs production or before vs after a UI change.
---

# Visual comparison: X and Y web application testing

Compare two web application environments for functional and visual parity, and publish the
screenshot pairs for PR review.

## When to use

The user asks to compare two web applications: "compare localhost:3000 and localhost:3001",
"compare staging and production", "compare before and after".

## Inputs from the user

1. **X**, the baseline, as a URL or instructions to start it.
2. **Y**, the comparison environment, as a URL or instructions to start it.
3. **Routes.** Routes the user names are always included. Beyond them the skill builds its own
   coverage plan: the routes and states the diff against `origin/master` affects, then
   Mixpanel-tracked critical paths, then discovered routes.
4. **API key**, if required, passed as a `token=<api-key>` query parameter.
5. **Screen size**, such as `1920x1080`, `1440x900` or `1280x720`. If the user gave none, ask
   before starting. Applications are designed for different viewports, and the choice decides
   how accurate the comparison is.
6. **Diff thresholds**, optional. Defaults: pixel sensitivity `10%` (a per-channel difference
   below it is not a changed pixel), largest contiguous changed region `1600 px` (roughly
   40x40), total changed fraction `0.2%`. A pair is **substantial** if either the region or
   the fraction threshold is exceeded, otherwise **good**. Only substantial pairs are findings,
   but every captured pair is published so a reviewer can check the verdict against the
   renders.

## Setup

### Upload preflight

The run ends by posting images through the `image-upload` skill, and it is one of the
long-running callers that skill's "Preflight for long-running callers" section covers. Run
that preflight now, and ask for any recovery input in the same exchange as the screen size. A
passing preflight, or the user's recorded choice to run without uploads, is a precondition for
capture.

### Output directories

```
.visual-comparison/
  x/       # baseline screenshots
  y/       # comparison screenshots
  diff/    # masks, crops and diff images
```

Name files by route: `home.png`, `dashboard.png`, `settings_profile.png` (replace `/` with `_`,
strip the leading slash). For a state after an interaction, append a descriptor:
`dashboard_after-filter-apply.png`. Never commit the directory unless the user asks.

### Server management

Track who started each server.

- **User-started server crashes:** report the environment and the error, and wait for the
  user's go-ahead before resuming.
- **Skill-started server crashes:** restart it with the same command and resume where you left
  off.

Never change how a dev server starts. No switching bundlers (bypassing Rspack or Turbopack for
Webpack), no adding or removing flags such as `--webpack` or `--turbo`, no changing
environment variables such as `TURBOPACK` or `NODE_ENV`, no "temporary" workaround. If a
server hangs or crashes:

1. Remove stale build output, `<project>/src/dist` and `<project>/dist/` if they exist.
2. Restart it with the same command and configuration.
3. If it still fails, stop the comparison, report the error, environment and route, and wait
   for the user.

### Viewport

X and Y run at exactly the same resolution for the whole run. At different sizes responsive
layouts reflow and the diff drowns in false positives.

```bash
agent-browser --session x set viewport <width> <height>
agent-browser --session y set viewport <width> <height>
```

- **Verify on the file, not the setting.** `--full` screenshots are sized by content width,
  so a page overflowing by one pixel yields a 1921-wide capture from a 1920 viewport. After the
  first capture on each session, check
  `magick identify -format '%w' .visual-comparison/x/<route>.png` against the agreed width. A
  wider capture means the page overflows horizontally. That is a finding, and the pair stays
  comparable only if X and Y overflow by the same amount. Pin `deviceScaleFactor` to 1 where
  the tool allows; a 2x DPR doubles every capture and passes a viewport query.
- **Re-apply after any restart** of a browser, a server or a token, to both sessions, even if
  only one restarted.
- **Differing widths for the same route** prove the viewports diverged. Re-apply to both and
  re-take both screenshots; never fix it in post-processing.

### Authentication

Every direct navigation carries the token: `?token=<api-key>`, or `&token=<api-key>` when the
URL already has a query. A direct navigation is any `agent-browser open`, reload, retry, or
link that triggers a full page load. Clicking an in-app link that drives the client-side
router keeps the session and needs no token. The first navigation in each session must carry
it: an unauthenticated visit redirects to an auth route, which can crash the dev server (for
example through ESM import errors in auth API routes like `supports-color`). That crash is
pre-existing, not a bug in the PR.

**The token-to-session race.** The frontend applies the token asynchronously after load, so
API requests that fire first return 401 and may redirect to a sign-in page on another domain.
Warm up each session:

1. Open the root URL with the token and wait for `networkidle`.
2. Check the current URL (`agent-browser --session <s> get url`). Still on the app's domain
   and not on an auth route means the session is applied.
3. Otherwise re-open the root URL with the token once. One retry rules out the race.

A 401 or sign-in redirect resolved by that one retry is the race; note it and continue. One
that persists after the retry, or appears mid-session after the session worked, is an expired
token:

1. Stop testing, and do not screenshot the sign-in page.
2. Report the environment and route, and why it looked like expiry.
3. Ask the user to run `fbctl user assume <company> <user>` again and provide the new token.
4. Re-run the warm-up in both sessions, then resume from the route that failed.

Without a token from the user, `fbctl user assume <company> <user>` prints a URL whose `token`
query parameter is the key.

## Procedure

### 1. Verify both environments

```bash
agent-browser --session x open "<X_URL>?token=<api-key>"
agent-browser --session y open "<Y_URL>?token=<api-key>"
```

This is the warm-up from Authentication. If either fails to load, report it and follow the
server rules.

**Establish baseline equivalence.** X must differ from Y only by the change under test.
Record the commit each environment serves and confirm X is at the branch's merge base
(`git merge-base origin/master HEAD`). A deployed baseline is usually behind it, and any commit
in the gap is a candidate explanation for a diff you would otherwise blame on the change. If X
cannot be brought to the merge base, state the gap up front and mark every verdict
provisional.

### 2. Build the coverage plan from the diff

What the PR changed drives what to capture. Before navigating beyond the warm-up:

1. **Read the diff**, not just the file names:

   ```bash
   git fetch origin master
   git diff origin/master...HEAD --stat
   ```

2. **Map changed files to routes with the render-path tracer** (below), not grep. A changed
   shared component can affect many routes; pick a representative set across different
   contexts. Trace manually only where the tracer emits no path or the project is not
   TypeScript.
3. **Resolve how each route is entered, now.** For each `(/route)` the tracer emitted, open
   its page component and list the parameters it reads: `router.query.<name>`, `useParams()`,
   dynamic segments (`[id].tsx`). A route that reads none is entered directly. For each
   parameter, find the view that produces it:

   ```bash
   rg -n "'/dashboard/shift-group'|\"/dashboard/shift-group\"" src/   # the pathname literal
   rg -n "router\.push|navigate\(|history\.push" src/ | rg "groupId"  # the param name
   ```

   A hit like

   ```js
   // views/dashboard/dashboard-menu.tsx:88
   const onSelectGroup = (groupId: string) => {
     const pathname = dashboardItemType === DashboardItemType.SHIFT
       ? '/dashboard/shift-group' : '/dashboard/batch-group';
     router.push({ pathname, query: { ...router.query, groupId } });
   };
   ```

   is the entry path: from the shift dashboard, the config menu, the group sidebar, then a
   group. Pass the producer to the tracer to find its route, and record the click chain.
   Every route gets an entry path, `direct` or a click chain, or is recorded `unreachable`
   with what you searched. Failing to hand-assemble a URL says nothing about reachability; the
   app produces the parameter values, so find where.
4. **Resolve each state's data precondition and pick a fixture** (see "Data-gated states").
5. **Map changes to states, not just routes.** A change in a modal, dropdown, tab, empty state
   or error state does not show in the default page. Every `[click ...]`, `[tab ...]`,
   `[data ...]` and `[state ...]` hop in a breadcrumb is an interaction or fixture to satisfy
   in step 3d.
6. **Prioritise:**
   - **Priority 0.** Routes the user listed.
   - **Priority 1.** Diff-affected routes and states. All of them are captured.
   - **Priority 1.5.** Interaction traversal of changed components (step 3d). A changed
     component behind a dialog, tab, drawer, dropdown or accordion is opened and captured;
     one behind a data gate gets a fixture that renders it. The host page alone does not
     cover it.
   - **Priority 2.** Mixpanel-tracked critical paths.
   - **Priority 3.** Remaining discovered routes.

Record the plan as rows of changed file, breadcrumb (pasted verbatim from the tracer), entry
path and fixture. It feeds the report and the PR comment. Capture starts only when every row
has an entry path and a fixture.

#### The render-path tracer

The tracer computes the path from a route to a changed component with the TypeChecker of the
project under test: its own `typescript` package, `tsconfig.json` and path aliases, never a
global compiler. It ships at `scripts/trace-render-paths.mjs`, relative to this file. Run it
from the application's source root:

```bash
cd <app project root>
node <skill-dir>/scripts/trace-render-paths.mjs ExportDialog src/components/FilterPanel.tsx
node <skill-dir>/scripts/trace-render-paths.mjs --json --max-paths 5 <Component|file>...
```

Targets are PascalCase component names or changed file paths. It builds a reverse render
graph through imports and aliases, analyses the guard on each render edge
(`{open && <Dialog/>}`, ternaries, `<Dialog open={...}>`, `<TabPanel value=...>`), and resolves
which `on*` handler flips the guard, one level of named-handler indirection deep. Guards no
handler flips are checked against the component's data hooks and reported as data gates. It
prints one breadcrumb per path, root first:

```
== ExportDialog — src/components/ExportDialog.tsx ==
  (/reports) ReportsPage ▸ ReportsToolbar ▸ [click "Export" → opens ExportDialog] ExportDialog

== AdvancedPanel — src/components/AdvancedPanel.tsx ==
  (/reports) ReportsPage ▸ ReportsToolbar ▸ [click "Export" → opens ExportDialog] ExportDialog ▸ [tab "advanced"] AdvancedPanel
```

Breadcrumb grammar:

- `(/route)`: a route entry point under Next.js `pages/` or `app/`. `(unrouted: <file>)` means
  dead code or a router config the tracer does not model.
- `▸`: static nesting; the parent always renders the next crumb.
- `[click "<label>"]`: the labelled element's handler reveals the next crumb.
- `[tab "<value>"]`: a tab panel selected by that value.
- `[data <expr> — needs fixture]`: the guard is decided by query data. No click reveals it;
  it needs a fixture.
- `[state <expr> — trigger?]`: guarded, with neither trigger nor data source resolved. Resolve
  it from source and an interactive snapshot, and check whether it is a data gate the tracer
  missed (state written from a `useEffect` over query data).
- `[inside <Container>]`: nested in a dialog, drawer or menu whose guard was not analysable.

The `(/route)` prefixes are Priority 1 routes, and every breadcrumb with an interaction or data
hop is a Priority 1.5 entry. Use each breadcrumb verbatim as its row key in the report and the
comment. The output is a high-recall draft: dynamic component maps, render props, portals and
non-file-based routers are not modelled. Where it is blind, trace manually and record which
paths you derived that way. It finds triggers; it does not certify them side-effect free.

#### Data-gated states

Many states render only for entities whose data satisfies a condition, and no amount of
clicking on the wrong entity reveals them. These are the states runs miss most, because the
page loads, the click works, and the component is simply absent.

Recognise a data gate from the guard:

- `[data ... — needs fixture]` says so outright.
- `[state ... — trigger?]` is one whenever the expression turns out to derive from query data.
- A `[click ...]` that does not reveal the component is often a clearing handler on a data
  gate.
- A trigger can itself depend on data: a "N unregistered stops" banner is inert on a line with
  zero stops.
- Landing on an empty state (`No Golden Batch found`, `Select a product`) means the fixture is
  wrong, not that the state is unreachable.

For each data-gated state, before capture:

1. Write the concrete condition from the guard chain: "a (line, product) pair with a current
   or pending golden batch", "a line with at least one unregistered stop in the window".
2. Find an entity that satisfies it, in this order: query the backend with the component's
   own GraphQL query over the candidates; walk the in-app picker for about five candidates,
   widening the time range before the candidate set; ask the user.
3. Record the fixture by identity (line name and id, product, group, batch). Both
   environments use it.

"First row under a stable sort" is for choosing between equivalent entities and does not apply
here; the first row is the likeliest to render an empty state. A bounded search that finds
nothing is a real result: record `unreachable (no qualifying fixture)` with the condition and
the candidates searched, in the plan, before capture.

#### Dropping a planned path

A planned breadcrumb leaves the plan only with one of these reasons and its evidence:

| Reason | Evidence required |
|---|---|
| `not traversed (depth cap)` | more than 2 interaction hops below the page |
| `skipped (mutation)` | `useMutation`, `client.mutate` or a `mutation` gql tag reached by the trigger's own handler |
| `blocked` | the concrete failure: HTTP status and endpoint, error overlay text, persistent redirect |
| `unreachable` | the producer search from step 3, recorded in the plan before capture |
| `unreachable (no qualifying fixture)` | the condition and candidates from step 4, recorded in the plan before capture |

"Could not figure out how to get there" is not a reason. `not captured (search incomplete)`
may name a gap in a run still in progress, never a published one. If something genuinely
prevents finishing (the environment cannot produce the fixture, the user's time box ran out),
get the user's call before posting the comment.

### 3. For each route in the plan

Use separate sessions, `--session x` and `--session y`.

#### a. Navigate

```bash
agent-browser --session x open "<X_URL>/<route>?token=<api-key>"
agent-browser --session x wait --load networkidle
agent-browser --session y open "<Y_URL>/<route>?token=<api-key>"
agent-browser --session y wait --load networkidle
```

Omit the token when the user gave none. Prefer clicking an in-app element over opening a
discovered URL.

#### b. Readiness gate

`networkidle` is not enough: data often arrives after the network settles, and an early
screenshot poisons the diff. Before every screenshot, in each session independently:

1. **No errors.** `agent-browser --session x errors`. If requests failed, go to network error
   triage rather than waiting.
2. **Correct URL**, still on the route and the app's domain.
3. **No loading indicators** in `agent-browser --session x snapshot --json`: `progressbar`,
   `status` or `alert` roles with loading text; `skeleton`, `shimmer`, `placeholder`,
   `loading`, `spinner`, `loader` classes; `aria-busy="true"`, `aria-label="Loading"`.
4. **Real content** in the main region: rows, charts, text. An empty shell is still loading,
   or its request failed.
5. **Stable.** Two snapshots about 2 seconds apart match.

Re-check every 2 seconds for about 30 seconds. A page still not ready then is **blocked**:
record why (a failed request, a stuck spinner, a redirect) and move on. Never screenshot a
half-loaded page. Only a settled page with a benign live widget gets captured anyway, with a
note.

##### Network error triage

Document the cause; do not fix it.

1. Identify each failing request: URL, status or connection failure, the feature that depends
   on it.
2. Classify:
   - **401:** usually the token race or an expired token. Apply the Authentication procedure.
     This is the one class you resolve, since testing cannot proceed without auth.
   - **Connection refused or timeout:** the backend is down. Note the host and port; continue
     with routes that do not depend on it, otherwise stop and report.
   - **5xx:** a backend bug or dependency. Record endpoint, status and body.
   - **404 on an API call:** a route or parameter mismatch. Note whether it happens in both
     environments.
   - **CORS, DNS, TLS:** environment configuration. Record the exact error.
3. An error in both X and Y is pre-existing and out of scope. One only in Y is a finding.
4. Record backend and environment causes under "Routes blocked by network errors" and move on.
   Dev-server error overlays are section 4.
5. Retry only transient causes, once.

#### c. Screenshot the initial load

```bash
agent-browser --session x screenshot --full .visual-comparison/x/<route_name>.png
agent-browser --session y screenshot --full .visual-comparison/y/<route_name>.png
```

Record the render path for every screenshot at capture time: the tracer's breadcrumb, or the
component chain from your source tracing, such as `(/dashboard) DashboardPage > FilterPanel >
DateRangeDialog`. It is the row key in the report and the comment.

#### d. Priority 1.5: interaction traversal

Right after the diff-affected default states, open what reveals each changed component. Tab
panels, dialogs, drawers, dropdowns and popovers are capture targets in their own right. If
every screenshot so far is a default page load, this phase has not run yet.

Reaching a parameter-gated route is an interaction too: go to the route hosting the producing
control, click through the recorded chain, and capture the destination with the destination's
render path. Selecting a fixture (a line picker, a product selector) is part of the traversal:
do it in both sessions, with the same values, in the same order.

For each changed component, parameter-gated route and data-gated state:

1. **Route and fixture** from the plan. A missing entry path or fixture means the plan is
   incomplete; do that search now.
2. **Trigger** from the `[click ...]` and `[tab ...]` hops, confirmed in
   `agent-browser --session <s> snapshot -i --json`. Resolve `trigger?` and `[inside ...]` hops
   by hand.
3. **Classify the trigger by its handler, read in source**, never by its label:
   - **Open:** switches a tab, opens a dialog, drawer, menu or popover, expands a section.
     Safe.
   - **Read-only submit:** sets local state, updates the router or query string, or fires a
     GraphQL query. Safe, and it must be traversed, since for many components it is the only
     way the state exists. "Generate report" whose handler is `setReportInput(input)` is one.
   - **Mutate:** `useMutation`, `client.mutate` or a `mutation` gql tag reached by the
     trigger's own handler. Never click. Capture the pre-interaction state and record
     `skipped (mutation)`.

   A mutation elsewhere in the opened component does not make opening it a mutation: open the
   history dialog, never press its save. When the handler stays ambiguous after you read it,
   treat it as mutate and say so.

   ```bash
   rg -n "generateReport|onSubmit|handleGenerate" src/views/reports/
   ```

4. **Same entity in both sessions.** Use the plan's fixture, or else the first row under a
   stable sort, or a named fixture present in both.
5. **Interact** on X and Y: fixture selection first, then the trigger, identically.
6. **Run the readiness gate** on the revealed state in each session; dialogs often lazy-load.
7. **Confirm the component rendered**, by its own markup (the dialog title, the card), not the
   container. An empty state means the fixture is wrong: pick another candidate and retry.
   A screenshot of an empty state counted as coverage shows the reviewer nothing.
8. **Screenshot both** as `<route>_<component>-open.png` and record the render path down to the
   opened element.
9. **Reset** both sessions: close the dialog, switch back the tab, or re-open the route with
   the token.

**Depth cap:** two interaction levels below the page, such as a dialog and a tab inside it.
Record deeper states as `not traversed (depth cap)`. The cap counts hops that reveal new
state. Navigating in through a producer and selecting the fixture are the cost of reaching the
page, so a line picker, a product picker and the card they reveal are one level.

#### e. Priority 2: Mixpanel-tracked components

Components that fire Mixpanel events are the critical paths after the diff-affected ones.

1. Search the source for `mixpanel.track(`, `Mixpanel.track(`, `track(` from a shared
   analytics module, `useTracking()` or `useAnalytics()`, and event-name literals.
2. For each, record the event name, the route that renders it, and the interaction that fires
   it.
3. Screenshot the default state in both sessions. If the interaction is an open or read-only
   submit, perform it and take `<route>_after-<interaction>.png` too. If it would mutate or
   send an API call beyond navigation, capture only the pre-interaction state and note it.

#### f. Priority 3: discovered routes

Discover routes from `/` by following the UI, not by constructing URLs; many need identifiers
only the app provides. Read the router config (React Router `<Route>`, Next.js `pages/` or
`app/`, Vue Router) for the map, cross-reference the snapshot for clickable elements, and
trace each `onClick` to confirm it navigates (`router.push`, `navigate()`, `history.push`, a
Next.js `Link`) and does not mutate, by the classification in step 3d. Skip and note what you
cannot confirm.

Check `next.config.js` for `trailingSlash`. With `true`, routes end in `/`; with `false` or
unset, they do not. The wrong form 404s or redirects.

#### g. Functional equality

1. Compare `agent-browser --session x snapshot -i --json` with Y's. Report any interactive
   element present in one and missing in the other.
2. Every discovered route and safe navigation target should work in both. Flag one that works
   in only one.
3. Perform the same non-mutating interactions on both and compare the resulting state.
4. List elements skipped as mutations or unconfirmed.

#### h. Matching resolutions

```bash
x_size=$(magick identify -format "%wx%h" .visual-comparison/x/<route>.png)
y_size=$(magick identify -format "%wx%h" .visual-comparison/y/<route>.png)
```

- **Both widths must equal the agreed width**, not just each other. Two 1921-wide captures on
  an agreed 1920 match and still overflow.
- **Widths differ:** the viewports diverged. Never pad. Re-apply the viewport to both and
  re-take both.
- **Widths agree but exceed the agreed width:** the page overflows. Comparable, and said so in
  the report.
- **Heights differ at the same width:** a real content difference, often a finding. Pad the
  shorter image with white at the bottom to the shared width and the larger height:

```bash
magick .visual-comparison/x/<route>.png -background white -gravity NorthWest -extent <width>x<max_height> .visual-comparison/x/<route>.png
magick .visual-comparison/y/<route>.png -background white -gravity NorthWest -extent <width>x<max_height> .visual-comparison/y/<route>.png
```

This padding is the one in-place edit in the pipeline; it only adds white below existing
content.

#### i. Mask dev-server indicators and volatile regions

Dev servers render indicators that are not the application: the Next.js dev indicator in the
bottom-right, Vercel and Turbopack badges, hot-reload overlays, "development mode" banners.
Volatile content belongs in the same mask: timestamps, relative times, avatars, live charts,
animation frames.

Find each bounding box from the screenshot or the DOM (`[data-nextjs-toast]`,
`nextjs-portal`), or mask a conservative corner such as the bottom-right 300x80px. Write the
masked copies to new files, one `magick` call per side carrying every rectangle:

```bash
magick .visual-comparison/x/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" \
  .visual-comparison/diff/<route>_masked-x.png
magick .visual-comparison/y/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" \
  .visual-comparison/diff/<route>_masked-y.png
```

Never write a mask back over `x/<route>.png` or `y/<route>.png`; those are the files the
comment publishes, and a loop like `for img in "$X" "$Y"` writing in place defaces them. Apply
the same rectangles to both sides, or the mask itself becomes a difference. Both the composite
in step j.1 and the `compare` in step j.4 read the masked pair. With nothing to mask, both
read `x/` and `y/` directly. List every masked region in the report.

#### j. Visual verdict

Each pair gets one verdict: **good** (assumed equal) or **substantial** (a real change). A flat
pixel percentage is a poor gate: a changed button label touches about 0.03% of pixels and an
invisible background shift touches 100%. The gate suppresses noise and then looks for one
contiguous changed region.

1. **Changed-pixel mask and percentage.** Use the per-channel max difference, not grayscale,
   whose luma weights discount pure-blue changes. Blur and open to drop anti-aliasing noise:

   ```bash
   magick .visual-comparison/diff/<route>_masked-x.png .visual-comparison/diff/<route>_masked-y.png \
     -alpha off -compose difference -composite \
     -separate -evaluate-sequence Max \
     -blur 0x1 -threshold 10% \
     -morphology Open Disk:1 \
     .visual-comparison/diff/<route>_mask.png

   pct=$(magick .visual-comparison/diff/<route>_mask.png -format "%[fx:100*mean]" info:)
   ```

   The mean of the binarised mask is the changed fraction.

2. **Cluster the mask:**

   ```bash
   magick .visual-comparison/diff/<route>_mask.png \
     -define connected-components:verbose=true \
     -define connected-components:area-threshold=40 \
     -connected-components 8 null:
   ```

   Take the largest non-background blob. Its bounding box says where the change is.

3. **Verdict.** A largest region of 1600 px or more, or a changed fraction of 0.2% or more, is
   substantial (or the user's thresholds). Anything else is good: record it with its
   percentage and do not report it as a finding. Good pairs are still published.

4. **For substantial pairs only:**
   - A red-highlight diff. `compare` exits 1 when images differ, so guard it:

     ```bash
     magick compare -fuzz 10% -highlight-color red -lowlight-color white \
       .visual-comparison/diff/<route>_masked-x.png .visual-comparison/diff/<route>_masked-y.png \
       .visual-comparison/diff/<route>.png 2>/dev/null || true
     ```

   - A one-line summary: map the largest blob's box to the component under it and say what
     changed. "FilterPanel apply-button row shifted ~4px down; button color changed".

### 4. Dev-server errors in Y

Watch for errors that stop a page rendering while the server runs: `Module not found`,
`SyntaxError: Cannot use import statement outside a module`, `Cannot find module 'foo'`,
TypeScript or bundler error overlays, error boundaries with stack traces. They are fixable in
source.

1. Halt the comparison; the error may affect many pages.
2. Diagnose from the message, stack trace and source.
3. Make the smallest fix that clears the error, nothing related to the PR's own work.
4. Ship it as its own draft PR: branch `fix/visual-comparison-<short-description>` off the
   PR's base, commit only the fix, push, and open a draft through `pr-description`. Then
   stack the PR branch on it (rebase the PR branch onto the fix branch and retarget its base),
   so the fix is reviewed and merged on its own and is not part of the PR's diff.
5. Restart the comparison from the beginning, since the fix may affect captured routes.

Only Y. Errors in the X baseline are reported to the user, who decides.

### 5. Crashes

Watch for 5xx pages, blank pages, browser errors and refused connections. Handle a crash by
the server rules in Setup. After any recovery (a server restart, a session re-open, a token
rotation), re-run the warm-up and re-apply the viewport to both sessions.

### 6. Report

**Reconcile first.** Check every planned breadcrumb against the files in
`.visual-comparison/x/`. Each appears in the reconciliation table with a screenshot or a reason
from "Dropping a planned path". A missing row sends you back to capture, not to the write-up.
Every row without a screenshot needs one of the five reasons, specific evidence, and evidence
produced in the plan before capture.

Re-read each drop reason before publishing it. A claim about the app ("not reachable from the
UI", "no such trigger") gets checked against the producer or fixture search, not against
memory. If a published reason turns out wrong, correct it and capture the path. Several
uncaptured rows with no substantial findings behind them usually mean capture was mis-scoped:
modal, tab and data-gated states are where a change to shared plumbing shows.

```markdown
## Visual comparison report

### Coverage plan reconciliation
| Planned render path | Captured | Reason if not |
|---|---|---|
| (/dashboard) DashboardPage ▸ [click "Export"] ExportDialog | yes | |
| (/dashboard/shift-group) DashboardGroupShift ▸ GroupShiftDashboard | yes | fixture: group "Packaging AM", entered via group sidebar (`dashboard-menu.tsx:88`) |
| (/reports) ReportsPage ▸ DeleteConfirm | no | skipped (mutation). Handler calls `useMutation(DELETE_REPORT)` |
| (/insights/golden-batch) GoldenBatchPage ▸ GoldenBatchCard | no | unreachable (no qualifying fixture). Needs a (line, product) pair with a golden batch; queried `goldenBatch` for all 14 lines and their products |

### Comparison verdicts
| Render path | Coverage reason | Verdict | X / Y files |
|---|---|---|---|
| (/home) HomePage | discovery | good 0.0002% | x/home.png, y/home.png |
| (/dashboard) DashboardPage > FilterPanel | diff: src/components/FilterPanel.tsx | substantial 0.84%. Apply-button row shifted ~4px | x/dashboard_filter-open.png, y/dashboard_filter-open.png |

### Mixpanel-tracked components
| Event name | Render path | Interaction | Verdict |
|---|---|---|---|
| "Filter Applied" | (/dashboard) DashboardPage > FilterPanel | click "Apply" | substantial |

### Functional differences
### Substantial visual differences
### Masked regions
### Routes blocked by network errors
### Authentication events
### Dev-server errors fixed (with the fix PR's URL)
### Crashes encountered
```

Every compared row carries its local X and Y paths; they become the image cells in the
comment. A section with nothing to report says "None".

### 7. Post the comparison to the PR

The upload, embedding and posting mechanics belong to the `image-upload` skill: the declared
backend, its upload step, the markdown wrapping. Use it for every file. If an upload fails on
auth mid-run, follow the backend's recovery step rather than posting text only. Skip images
only when the user declined them, and then say so in the report.

**One comment per PR.** A re-run edits the comment an earlier run posted
(`gh pr comment <number> --edit-last`, or a PATCH on its id) instead of posting another. A
run-over-run column is welcome context, and it replaces none of the image pairs.

**The verdict table carries the screenshots.** Every compared row shows its own X and Y image
inline beside its render path and percentage, good rows included; that is how a reviewer
catches what the thresholds missed, a mask that hid a chart, or a fixture that rendered an
empty state.

| Verdict | X and Y cells | Below the table |
|---|---|---|
| substantial | both images | crop, full-width pair, diff overlay |
| good | both images | none |
| blocked, skipped, not captured | empty | none |

- **Embed, never link.** Every image cell is `![alt](url)`; a cell starting with `[` is wrong.
- **Do not curate.** Fill the cells for every compared path, however many uploads that takes.
- **Show the percentage on good rows too.** `0.0000%` and `0.11%` say different things.
- **Key alt text to the render path**, `<route>-<component>-x` and `-y`.

```markdown
## Visual comparison: <X label> vs <Y label>

Viewport 1920x1080, <N> render paths compared, <M> substantial, <K> not captured.

| Render path | Verdict | X (before) | Y (after) |
|---|---|---|---|
| `(/) Lines ▸ LineCard ▸ Chart` | substantial 1.56%, largest region 88x95px | ![lines-x](…) | ![lines-y](…) |
| `(/operator) OperatorView` | good 0.0000% | ![operator-x](…) | ![operator-y](…) |
| `(/reports) ReportsPage ▸ ExportDialog` | blocked, API 503 in Y | | |
| `(/insights/golden-batch) … ▸ GoldenBatchCard` | not captured, no line/product pair has a golden batch | | |

### `(/) Lines ▸ LineCard ▸ Chart`, 1.56%
Trace deviates up to 12px per point, axis ticks shifted.

| X | Y |
|---|---|
| ![lines-crop-x](…) | ![lines-crop-y](…) |

<details><summary>Expand for the full page and the diff overlay</summary>

| X | Y |
|---|---|
| ![lines-full-x](…) | ![lines-full-y](…) |

![lines-diff](…)
</details>

_Masked from every diff: dev-server indicator, live throughput chart._
```

**Crop where a full page cannot show the change.** For a shifted axis or a few pixels of
deviation, crop the largest blob's padded box from step j.2, the same box on both sides, and
lead that path's section with the crop:

```bash
magick .visual-comparison/x/<route>.png -crop <w>x<h>+<x>+<y> +repage .visual-comparison/diff/<route>_crop-x.png
magick .visual-comparison/y/<route>.png -crop <w>x<h>+<x>+<y> +repage .visual-comparison/diff/<route>_crop-y.png
```

**Check before posting.** The filled image cells number exactly twice the good and substantial
rows, and every image cell starts with `![`.

Give the comment URL in the final report.

## Cleaning up

`.visual-comparison/` is local working state. The PR comment is the durable copy, so the
directory can be removed after the PR merges.
