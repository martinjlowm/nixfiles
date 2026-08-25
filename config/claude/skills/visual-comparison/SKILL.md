---
name: visual-comparison
description: Compares two web application environments (X and Y) across all navigatable pages for functional and visual parity, producing screenshot documentation for PR reviews
---

# Visual comparison: X and Y web application testing

Compare two web application environments to verify functional and visual parity. Produces screenshot documentation suitable for PR review.

## When to use

When the user asks to compare two web applications: "compare localhost:3000 and localhost:3001", "compare staging and production", "compare before and after".

## Inputs from the user

1. X, the baseline environment, as a URL or instructions to start it
2. Y, the comparison environment, as a URL or instructions to start it
3. Pages and routes to navigate. The user may specify routes, and those are always included. Beyond that, the skill builds its own coverage plan: first the routes and states affected by the diff against `origin/master` (see "Build the coverage plan"), then Mixpanel-tracked critical paths, then generally discovered routes
4. API key, if required. Passed as a `token=<api-key>` query parameter on all requests
5. Screen size, optional. Viewport dimensions for screenshots (`1920x1080`, `1440x900`, `1280x720`). If the user does not specify one, **ask them before starting the comparison**. Do not assume a default. Different applications are designed for different viewports and the choice affects how accurate the comparison is.
6. Diff thresholds, optional. The gate that decides whether a diff is **substantial**, a real change someone should look at, or the pair is assumed equal. Defaults: pixel sensitivity `10%` (a per-channel difference below this is not a changed pixel), largest contiguous changed region `1600 px` (roughly 40x40), total changed fraction `0.2%`. A pair is substantial if **either** the region or the fraction threshold is exceeded, otherwise it is marked good. Only substantial diffs are reported as findings, but every captured pair is uploaded to GitHub so a reviewer can check the verdict against the actual renders.

## Setup

### GitHub upload preflight

The final step posts before and after images to the PR via the **gh-image-upload** skill, which authenticates with a GitHub `user_session` token. That is an interactive dependency and cannot be resolved mid-run in a headless session. Run its preflight **now**, before any capture work:

```bash
gh image check-token
```

If it fails, follow gh-image-upload's authentication section to request the token from the user, at the same time as asking for the screen size, while they are present. Do not defer this to the upload step. A token discovered missing after the comparison finishes leaves the report without its images. If the user opts to run without uploads, record that decision and note it in the report. Otherwise a passing `check-token` is a precondition for starting the comparison. All token mechanics (extraction, validation, expiry recovery, handling) belong to gh-image-upload. Do not restate or improvise them here.

### Screenshot output directories

Create two directories at the repository root for storing screenshots:

```
.visual-comparison/
  x/       # baseline screenshots
  y/       # comparison screenshots
  diff/    # ImageMagick diff images
```

Name screenshot files by route: `home.png`, `dashboard.png`, `settings_profile.png`. Replace `/` with `_` and strip the leading slash. For stateful pages, such as after clicking a button, append a descriptor: `dashboard_after-filter-apply.png`.

### Server management

- User-started servers: if the user started the servers, do NOT restart them on crash. Report the crash clearly, naming the environment and the error if visible, and wait for the user's explicit go-ahead before resuming testing.
- Skill-started servers: if you started a server as part of the comparison setup, recover from crashes by restarting it automatically, then resume testing where it left off.

**CRITICAL: do not modify server setup. No exceptions.** You must NEVER change how the dev server is started. That includes:
- Switching bundlers, such as bypassing Rspack or Turbopack to use Webpack
- Adding or removing CLI flags such as `--webpack` or `--turbo`
- Setting, unsetting, or changing environment variables such as `TURBOPACK` or `NODE_ENV`
- Killing hanging server processes to restart with different configuration
- Any other "temporary" or "just for the comparison" workaround

The server configuration stays **exactly** as the project defines it. If the server hangs, crashes, or misbehaves:

1. Clear cached build outputs. Remove `<project>/src/dist` and `<project>/dist/` if they exist. Stale caches are a common cause of hangs.
2. Restart the server **with the same command and configuration as before**.
3. If it still hangs or crashes after clearing caches, **stop the comparison entirely**, report the problem to the user with full details (error messages, which environment, which route triggered it), and **wait for explicit user instructions**.

Do not try to diagnose or work around server infrastructure problems by modifying the server setup.

Track who started each server so you handle crashes correctly.

### Viewport and screen size

**CRITICAL: X and Y MUST run at the exact same resolution.** Every pixel-level comparison in this skill is meaningless if the two sessions render at different viewport sizes. Responsive layouts reflow, breakpoints flip, and the diff drowns in false positives. Identical resolution is an invariant to enforce for the entire run, not a one-time setup step.

Set the browser viewport on both sessions before taking any screenshots:

```bash
agent-browser --session x set viewport <width> <height>
agent-browser --session y set viewport <width> <height>
```

Use the dimensions the user provided. If the user did not specify a screen size, **you must ask them before proceeding**. Suggest a few common options such as 1920x1080, 1440x900, or 1280x720, but let them choose.

Enforce the invariant:

1. Verify on the **artifact**, not the setting. A viewport query is not proof. `--full` screenshots are sized by *content* width, not viewport width, so a page that overflows horizontally by a pixel yields an off-spec capture from a perfectly set viewport:

   ```
   {innerWidth:1920, dpr:1, docW:1921}   ->   captured PNG: 1921x1144
   ```

   So after the first capture on each session, assert the file itself:

   ```bash
   magick identify -format '%w' .visual-comparison/x/<route>.png   # must equal the agreed width
   ```

   A capture wider than the agreed width means the page overflows horizontally. That is a finding in its own right. Record it, and treat the pair as comparable only if X and Y overflow by the **same** amount. Also pin `deviceScaleFactor` to 1 where the tool allows it: a 2x DPR silently doubles every capture and passes a viewport query unnoticed.
2. Re-apply after any browser or server restart. A crash recovery, token rotation, or session re-open resets the viewport. Always re-apply the viewport to **both** sessions back to the agreed dimensions before resuming, even if only one session restarted.
3. Check before diffing. Screenshots for the same route whose **widths** differ prove the viewports diverged. Do not "fix" this in post-processing. Stop, re-apply the viewport to both sessions, and re-take both screenshots.

### Authentication

If the user provides an API key, append `?token=<api-key>` to every URL when navigating, or `&token=<api-key>` if the URL already has query parameters. The API key applies to both X and Y.

**CRITICAL: authenticate before anything else.** The very first navigation in each browser session **must** include the `token=<api-key>` query parameter. If the browser session starts by visiting a URL **without** the token, the app tries to redirect to an auth or login route, which can crash the dev server, for example through ESM import errors in auth API routes like `supports-color`. That crash is **not** a bug in the PR. It is a pre-existing problem triggered by unauthenticated access, and the fix is simple: always include the token on the initial visit.

**CRITICAL: the token-to-session race.** The frontend reads the `token` query parameter and applies it to the session asynchronously after page load. API requests that fire **before** the token is applied return 401, and the frontend may react by redirecting to a sign-in page **on a different domain**. So a 401 or sign-in redirect early in a session does NOT automatically mean the token is expired. It may just be this race. To establish the session reliably in each browser session:

1. Navigate to the root URL with the token and wait for `networkidle`.
2. Check the current URL (`agent-browser --session <s> url`, or via a snapshot). If it is still on the app's domain and not an auth or sign-in route, the session is applied. Proceed.
3. If the browser landed on a sign-in page or a different domain, re-navigate to the root URL **with the token** and wait again. One retry is enough to rule out the race.
4. Only after this warm-up start visiting routes. On later navigations, still include the token in the URL, but the session cookie and storage should now carry authentication.

Telling the race apart from an expired token:
- A 401 or sign-in redirect on the **first** load of a session, resolved by one re-navigation with the token, is the session-application race. Note it in the report, naming the environment and route, and continue testing.
- A 401 or sign-in redirect that **persists after a retry with the token**, or appears **mid-session after the session was working**, means the token expired. Follow the key rotation procedure below.

Obtaining a token: if the user has not provided one, they can get one by running:

```bash
fbctl user assume <company> <user>
```

That outputs a URL. The token is in the URL's query parameters. Extract the `token=<value>` from it.

Key rotation. If a 401, 403, sign-in redirect, or "unauthenticated" or "session expired" message survives the race-retry above:

1. Stop testing immediately. Do not screenshot the sign-in page. It is not the route under test.
2. Report which environment and route triggered the auth failure, and note whether it looked like expiry, persisting after retry or appearing mid-session, rather than the session race.
3. The token has likely expired. Ask the user to run `fbctl user assume <company> <user>` again and provide the new token.
4. Once provided, re-run the session warm-up in **both** sessions, hitting the root URL with the new token and verifying no sign-in redirect, then resume testing from the route that failed.

## Procedure

### 1. Verify both environments are reachable and authenticated

```bash
agent-browser --session x open "<X_URL>?token=<api-key>"
agent-browser --session y open "<Y_URL>?token=<api-key>"
```

**Establish baseline equivalence before anything else.** X must differ from Y *only* by the change under test. Record the commit each environment serves and confirm X is at the branch's merge base (`git merge-base origin/master HEAD`, or the branch's second parent on a merge commit). A deployed baseline is usually behind it, and any commit in the gap is a candidate explanation for a diff you would otherwise attribute to the change. Verifying that X merely *lacks* the feature under test is not sufficient. If X cannot be brought to the merge base, state the gap up front and mark every verdict provisional.

This first navigation doubles as the session warm-up from the authentication section. Wait for `networkidle`, then verify each session is still on the app's domain, with no sign-in redirect and no auth-related network errors, before proceeding. If either fails to load, report it. Follow the crash-handling rules above.

### 2. Build the coverage plan from the diff against origin/master

The primary driver of what to traverse and screenshot is **what the PR changed**. Before navigating anything beyond the warm-up, derive the affected places from the diff:

1. Diff against the merge base:
   ```bash
   git fetch origin master
   git diff origin/master...HEAD --stat
   ```
   Then read the actual diff for the frontend-relevant files, not just the file names, so you know which components, hooks, styles, or route definitions were touched and how.
2. **Map each changed file to the routes that render it analytically, not by grep.** Run the render-path tracer (next subsection) against every changed component. It uses the project's own TypeScript TypeChecker to walk the reverse render graph and emits one breadcrumb per path from a route entry point to the component. A changed shared component, such as a design-system element, layout, or common hook, can affect many routes. From the tracer's paths, pick a representative set that exercises it in different contexts rather than exhaustively screenshotting every consumer. Fall back to manual import-chain tracing only where the tracer emits no path or the project is not TypeScript.
3. **Resolve how each route is entered, up front, for every route in the plan.** The tracer tells you a route renders the change. It does not tell you how a user gets there. Answer that now, while building the plan, for **every** `(/route)` it emitted. Discovering at capture time that you have no way in is already a failure: by then the route reads as an obstacle to route around rather than a step to work out, and the plan silently shrinks.

   For each route, open its page component and list every parameter it requires: `router.query.<name>`, `useParams()`, dynamic segments (`[id].tsx`). A route that reads none is entered by direct navigation, and you are done. For each parameter it does read, **find what produces it**. Some view in the app constructs that navigation, and that view is your entry point:

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

   is the entry path. The route is reached from the shift dashboard via the config menu, then the group sidebar, then picking a group. Trace the producing component back to *its* route, which the tracer does if you pass it the producer, and record the click chain. That chain is a Priority 1.5 entry, planned before capture begins rather than reconstructed after it fails.

   Record an entry path for every route, either `direct` or the click chain from a route you can reach directly. **A route with no entry path recorded is not ready to capture.** Either finish the search or record it as `unreachable` here, in the plan, with what you searched for. Do not carry an unresolved route into capture and decide there.

   **Never let URL construction stand in for this.** Failing to hand-assemble a working URL says nothing about whether a route is reachable, only that you do not have a parameter value yet. The app produces those values. Find where.
4. **Resolve the data precondition of every state, and pick a fixture that satisfies it.** See "Data-gated states and fixture selection" below. Do this now, in the plan, for every breadcrumb. A component that renders only when the data says so is not reachable by clicking harder, and discovering that at capture time is the same failure as discovering a missing route parameter there.
5. **Map changes to states, not just routes.** If the change lives in a modal, dropdown, tab panel, empty state, or error state, a screenshot of the default page state will not show it. The tracer's breadcrumbs make these states explicit. Every `[click ...]`, `[tab ...]`, `[data ...]`, and `[state ...]` hop is an interaction or a fixture requirement that must be satisfied, traversed in Priority 1.5, step 3d, and screenshotted before and after in both environments.
6. Produce a prioritized coverage plan:
   - **Priority 0.** Routes the user explicitly listed.
   - **Priority 1.** Diff-affected routes and states, from this section. These MUST all be traversed and screenshotted.
   - **Priority 1.5.** In-app interaction traversal of changed components (step 3d). A changed component whose visible state sits behind an interaction, such as a dialog, tab panel, drawer, dropdown, or accordion, MUST be opened and captured. One sitting behind a data gate MUST be given a fixture that renders it and captured. The page that hosts it is not enough.
   - **Priority 2.** Mixpanel-tracked critical paths (see below).
   - **Priority 3.** Remaining routes from general discovery.

Record the plan as a mapping of changed file, route or routes, entry path, fixture, and state or interaction. It feeds the report and the PR comment, so reviewers can see why each screenshot exists. The tracer's breadcrumbs (below) ARE the route and state half of this mapping. Paste them into the plan verbatim and add the entry path from step 3 and the fixture from step 4 to each.

The plan is complete only when every row has both an entry path and a fixture. Do not start capture with unresolved rows.

#### Analytical render-path tracing with the TypeScript TypeChecker

The path from a route to a changed component is computed statically with the **TypeChecker API of the project under test**: its own `typescript` package, `tsconfig.json`, and path aliases, never a globally installed compiler. The tracer ships with this skill at `scripts/trace-render-paths.mjs`, resolved relative to this SKILL.md's directory. Run it from the root of the application's source tree:

```bash
cd <app project root>
node <skill-dir>/scripts/trace-render-paths.mjs ExportDialog src/components/FilterPanel.tsx
node <skill-dir>/scripts/trace-render-paths.mjs --json --max-paths 5 <Component|file>...
```

Targets are PascalCase component names or changed file paths, which cover all components declared in the file. It builds a reverse render graph, resolving which component renders which through imports and aliases via the checker, analyzes the guard on each render edge (`{open && <Dialog/>}`, ternaries, `<Dialog open={...}>`, `<TabPanel value=...>`), and resolves which `on*` handler flips the guarding state, following one level of named-handler indirection. Guards no handler flips are checked against the component's data hooks and reported as data gates rather than as unresolved triggers. Output is one breadcrumb per path, root-first:

```
== ExportDialog — src/components/ExportDialog.tsx ==
  (/reports) ReportsPage ▸ ReportsToolbar ▸ [click "Export" → opens ExportDialog] ExportDialog

== AdvancedPanel — src/components/AdvancedPanel.tsx ==
  (/reports) ReportsPage ▸ ReportsToolbar ▸ [click "Export" → opens ExportDialog] ExportDialog ▸ [tab "advanced"] AdvancedPanel
```

Breadcrumb grammar:

- `(/route)` is a route entry point, following Next.js `pages/` and `app/` conventions. `(unrouted: <file>)` means no route was found, so either dead code or a router config the tracer does not model.
- `▸` is static render nesting. The parent renders the next crumb unconditionally.
- `[click "<label>"]` means this hop requires an interaction. The labeled element's handler sets the state revealing the next crumb. This is the trigger for Priority 1.5 step 2.
- `[tab "<value>"]` means the next crumb is a tab panel selected by that value.
- `[data <expr> — needs fixture]` means the guard is decided by query data, not by an interaction: bound off a `useQuery` result, or written only from a query's `onCompleted`. **No click reveals this crumb.** It is a data gate, and it needs the fixture search from section 2 step 4. This is the trigger for that step.
- `[state <expr> — trigger?]` means guarded, and the tracer could resolve neither a triggering element nor a data source. Resolve it manually, from source plus an interactive snapshot, before traversal. Check whether it is a data gate the tracer's heuristics missed, for instance state written from a `useEffect` over query data.
- `[inside <Container>]` means nested in a dialog, drawer, or menu whose guard prop was not statically analyzable.

How the breadcrumbs feed the run:

- Coverage plan: the `(/route)` prefixes are the Priority 1 routes, and every breadcrumb containing an interaction or data hop is a Priority 1.5 entry.
- Priority 1.5 steps 1 and 2: route and trigger are read directly off the breadcrumb. `trigger?` hops need manual resolution, `needs fixture` hops need a fixture search rather than a trigger. Step 3's open / read-only-submit / mutate classification stays mandatory. The tracer finds the trigger, it does not certify it side-effect-free.
- Render paths: a breadcrumb is a render path. Use it verbatim as the row key in the report and PR comment.

Treat the output as a high-recall draft, not ground truth. Dynamic component maps, render props, portals mounted from unrelated trees, and non-file-based router configs are not modeled. Where the tracer is blind, fall back to manual import-chain tracing plus snapshot exploration, and record in the plan which paths were derived manually.

#### Data-gated states and fixture selection

Not every state is behind a click. Many are behind **data**. The component renders only for entities whose data satisfies a condition, and no amount of clicking on the wrong entity reveals it. These are the states runs miss most often. The page loads fine, the interaction succeeds, and the component is not there, which reads as "nothing to capture" rather than "wrong fixture".

Recognize a data gate from the guard, not from the breadcrumb hop type:

- `[data <expr> — needs fixture]` is the tracer saying so outright: nothing flips this guard, the response decides it. Do not hunt for a button. Find an entity where the query returns something.
- `[state <expr> — trigger?]` is the same thing unlabeled whenever `<expr>` turns out to be derived from query data anyway, such as state written from a `useEffect` over a response, or a selector the tracer's heuristics did not follow. Read the guard's source before assuming a trigger exists.
- A `[click "<label>"]` on a *clearing* handler is a false trigger. If clicking the resolved element does not reveal the component, re-read the guard: it is usually a data gate whose setter also happens to be called from a reset button.
- A `[click "<label>"]` hop can still be data-gated when the trigger itself only appears, or only does anything, for qualifying data. A "N unregistered stops" banner that opens a dialog is inert on a line with zero stops.
- Empty-state and "no data" branches (`No Golden Batch found`, `Select a product`, `No lines available`) that you land on ARE the signal. Landing on one means the fixture is wrong, not that the state is unreachable.

For each data-gated state, resolve a fixture **before capture**:

1. Read the guard chain in source and write down the concrete condition: "a (line, product) pair with a current or best-pending golden batch", "a line with at least one unregistered stop in the window", "a line with a manual counter sensor", "a dashboard with at least one saved group".
2. Search the data for an entity that satisfies it. In order of preference:
   - Query the backend directly, with the same GraphQL query the component uses, over the candidate set. This answers the question once instead of N page loads.
   - Walk the in-app selector: open the line, product, group, or entity picker and try candidates. Stop at about five, or at the end of the list if it is shorter. Widen the time range before widening the candidate set, since many of these conditions are window-scoped.
   - Ask the user. They know which line in the test company has a golden batch, a manual counter, or unregistered stops. One question here is cheaper than an unbounded search, and much cheaper than a missing capture.
3. Record the chosen fixture in the plan by identity, the line name and id, product, group, batch, not as "the first one". Both environments MUST use that same fixture.

**The "first row under a stable sort" default does not apply to data-gated states.** It is the rule for picking *between* equivalent entities, where any of them would render the state. When the state exists for only some entities, the first row is the most likely one to render an empty state, which is exactly how these get dropped.

If the bounded search finds nothing, that is a real result: record `unreachable (no qualifying fixture)` with the condition and the search you ran, in the plan, before capture. That is a legitimate drop. "The component did not appear" is not.

#### Dropping a traced path requires evidence

Once a breadcrumb is in the plan, it is a commitment. A path may leave the plan only for a reason you can point at, and each reason has a required piece of evidence:

| Reason | Evidence required |
|---|---|
| `not traversed (depth cap)` | the breadcrumb has more than 2 interaction hops below the page |
| `skipped (mutation)` | the trigger handler's source shows `useMutation`, `client.mutate`, or a `mutation` gql tag **on the trigger itself**, not merely somewhere in the opened component |
| `blocked` | the concrete failure: HTTP status and endpoint, error overlay text, persistent redirect |
| `unreachable` | the producer search from step 3 came up empty, recorded in the plan **before** capture started |
| `unreachable (no qualifying fixture)` | the condition from the fixture search in step 4, plus the candidate set searched, recorded in the plan **before** capture started |

"I could not figure out how to get there" is not one of these, and at this point it is too late to become one. Entry paths and fixtures are resolved in steps 3 and 4, before capture. A path arriving at capture time without one means that step was skipped for it, so go back and do the search rather than inventing a reason here.

**`not captured (search incomplete)` is not a terminal state.** It is an admission that a required planning step was skipped, and it exists only so an in-progress run can name its own gap honestly. It is not a label you may publish. If reconciliation turns one up, the run is not finished: go back, finish the search, and capture the path. Something may genuinely prevent that, say the environment cannot produce the fixture or the user's time box is up. Then tell the user and get their call **before** posting the PR comment. Do not ship a comment whose reconciliation table is a list of searches you did not run.

### 3. For each route in the coverage plan

Do the following on both X and Y using separate browser sessions, `--session x` and `--session y`:

#### a. Navigate

```bash
agent-browser --session x open "<X_URL>/<route>?token=<api-key>"
agent-browser --session x wait --load networkidle
agent-browser --session y open "<Y_URL>/<route>?token=<api-key>"
agent-browser --session y wait --load networkidle
```

If no API key was provided, omit the `token` query parameter.

**In-app versus direct navigation, and the token rule.** There are two ways to reach a route, and they differ in whether the in-app session survives:

- In-app navigation means clicking anchors (`<a ...>`) or elements whose `onClick` handlers drive the client-side router. The in-app session is preserved, and no token parameter is involved in the click itself.
- Direct navigation means every `agent-browser open <url>`, page reload, retry, or link that triggers a full page load: an external href, `target="_blank"`, a non-router anchor. These do NOT preserve the in-app session, so the `token=<api-key>` query parameter must be supplied on **every** direct navigation, no exceptions. That includes re-navigations during the readiness gate, auth-race retries, and resuming after a crash or token rotation. A single tokenless direct navigation can bounce the session to the sign-in domain (see Authentication).

When discovery yields a URL to visit, prefer clicking the element in-app. If you navigate by URL instead, always append the token.

#### b. Readiness gate: the page must be fully loaded and error-free before any screenshot

`networkidle` alone is NOT sufficient. Data often arrives after the network settles briefly, and a page can look "idle" while still rendering skeletons or an error state. A screenshot taken too early poisons the diff for that route and produces false differences. Before **every** screenshot, all of the following must pass:

1. No network or console errors. Check for failed requests first. A spinner will never resolve if the request behind it failed:
   ```bash
   agent-browser --session x errors
   ```
   If errors are present, do not keep waiting for the page to settle. Go to "Network error triage" below.
2. Correct URL. Confirm the browser is still on the expected route and the app's domain, not redirected to a sign-in page (see "the token-to-session race" under Authentication) or an error page.
3. No loading indicators. Take a snapshot and look for:
   ```bash
   agent-browser --session x snapshot --json
   ```
   - Elements with roles like `progressbar`, `status`, or `alert` containing "loading" text
   - Skeleton and placeholder elements, with CSS classes like `skeleton`, `shimmer`, `placeholder`, `loading`
   - Spinner elements (`spinner`, `loader`, `loading-indicator`)
   - Aria attributes: `aria-busy="true"`, `aria-label="Loading"`
4. Content is actually present. The main content region must hold real content, such as data tables with rows, charts, or text, not an empty shell. A page with no loading indicators but also no content is still loading, or its data request failed, so re-check step 1.
5. Stability check. Take two snapshots about 2 seconds apart:
   ```bash
   agent-browser --session x snapshot --json   # first
   agent-browser --session x wait --timeout 2000
   agent-browser --session x snapshot --json   # second, must match the first
   ```
   If the two snapshots differ, content is still streaming in. Keep waiting and re-check.

If any check fails, wait and re-run the gate:
```bash
agent-browser --session x wait --timeout 2000
```
Repeat until all checks pass or about 30 seconds have elapsed. If the page is still not ready at timeout, do NOT silently screenshot a half-loaded page. Work out **why**: a failed request, a stuck spinner, a persistent redirect. Record the route as **blocked** with the cause in the report, and move on. Only if the page is genuinely settled but a benign indicator persists, such as a live-updating widget, should you screenshot anyway and note it.

Run the gate for **both sessions**, X and Y, independently. They load at different speeds, and each must pass on its own before its screenshot is taken.

##### Network error triage

When `agent-browser errors` shows failed requests, the page is not displaying as intended and a screenshot of it is not a valid comparison. The goal is to **understand and document the cause, not to fix it**. Network errors lead to tangent work. Resist that pull. Triage:

1. Identify the failing requests: URL, HTTP status or connection failure, and which page feature depends on it.
2. Classify the cause:
   - 401 Unauthorized is most often the token-to-session race, where API requests fired before the `token` query parameter was applied, or an expired token. Apply the authentication procedure: retry once with the token, and if it persists, treat it as expired and rotate the key. This is the ONE class of network error you actively resolve, because testing cannot proceed without auth.
   - Connection refused or timeout to a backend API means the API server behind the frontend is down or unreachable. Note which host and port, and continue to other routes if they don't depend on it. Otherwise stop and report.
   - A 5xx from a backend means a backend bug or an unavailable dependency. Record the endpoint, status, and response body if visible.
   - A 404 on an API call is usually a route or parameter mismatch. Record it, and note whether it happens in both environments, meaning pre-existing, or only one, which may be PR-related and is a genuine finding rather than noise.
   - CORS, DNS, and TLS errors are environment configuration. Record the exact error text.
3. Compare against the other environment. An error in both X and Y is pre-existing and out of scope. An error only in Y is a finding for the report.
4. Do not fix backend, infrastructure, or environment causes. Record the cause in the "Routes blocked by network errors" report section and move on. Frontend source errors that surface as dev-server error overlays are a different case, covered in "Development server error detection" below.
5. Retry only transient causes, the auth race or a one-off timeout, and only once. Never retry-loop against a consistently failing endpoint.

#### c. Screenshot the initial page load

Only after the readiness gate has passed in both sessions:

```bash
agent-browser --session x screenshot --full .visual-comparison/x/<route_name>.png
agent-browser --session y screenshot --full .visual-comparison/y/<route_name>.png
```

**Record the render path for every screenshot.** The render path is the endpoint plus the framework component nesting that produced the captured state. For traced components that is exactly the tracer's breadcrumb. Otherwise derive it from the source tracing done for the coverage plan. A React example: `(/dashboard) DashboardPage > FilterPanel > DateRangeDialog`. A default page-load state may be just the page component. An interaction state must include the component chain down to the opened dialog, panel, or tab. The render path is the row key for every table in the report and the PR comment, so record it at capture time rather than reconstructing it afterwards.

#### d. Priority 1.5: in-app interaction traversal of changed components

Immediately after the diff-affected routes' default states are captured, traverse the interactions that reveal each changed component. **Tab panels, dialogs, drawers, dropdowns, and popovers are first-class capture targets, not an optional extra on top of pages and routes.** A route whose changed component lives behind a tab or a dialog trigger is NOT covered by its default page-load screenshot. A run that only captures route-level pages has skipped this phase entirely, and that is the single most common way this skill silently under-delivers. If every screenshot you took is a default page-load state, you have not run this phase. Go back and run it before writing the report.

**Reaching a route is itself an interaction.** This phase is not only about components nested inside a page. A route that only exists once some other view supplies its parameter, such as `/dashboard/shift-group?groupId=...`, is entered exactly the way a dialog is opened: navigate to the route that hosts the producing control, click through it, and let the app hand you the parameter. Their entry paths are already in the plan from section 2 step 3, so this phase executes a click chain you resolved up front: the sidebar item, menu entry, table row, or card that calls `router.push`. Capture the destination once it loads, and record the render path of the destination route, not of the control you clicked.

**Selecting a fixture is itself an interaction.** A line picker, product selector, or group sidebar whose choice decides whether the changed component renders at all is part of the traversal, not setup noise. Perform the selection in both sessions, with the same values, in the same order, and only then gate and capture.

For **each changed component, each parameter-gated route, and each data-gated state** from the coverage plan, run this loop:

1. Resolve the route and fixture. Take the `(/route)` prefix from the component's breadcrumb (analytical render-path tracing, section 2), its recorded entry path, either `direct` or the click chain resolved in step 3, and its recorded fixture from step 4. If several breadcrumbs exist, pick one representative route per distinct context. If the entry path or fixture is missing, the plan was left incomplete: do that search now, before capturing anything else.
2. Identify the trigger. Read the `[click "<label>"]` and `[tab "<value>"]` hops off the breadcrumb, then confirm the element exists in the live page via the interactive snapshot (`agent-browser --session <s> snapshot -i --json`). For `[state ... — trigger?]` or `[inside <...>]` hops the tracer could not resolve, find the trigger manually: the tab, the "Edit" or "New" or row-click that opens the dialog, the menu item, the accordion header, the drawer toggle.
3. Classify the trigger by **what its handler does**, into one of three kinds. Read the handler in source; do not classify from the button's label.
   - **Open.** A pure UI state change: switches a tab, opens a dialog, drawer, menu, or popover, expands a section. Safe to click.
   - **Read-only submit.** A form or control whose submit handler only sets local state, updates the router or query string, or fires a GraphQL **query**. It writes nothing. Safe to click, and it MUST be traversed. For many components this is the only way the state exists at all.
   - **Mutate.** Fires a GraphQL mutation, or otherwise writes data. Never click. Capture the pre-interaction state only and record the component as `skipped (mutation)`.

   **A submit button is not a mutation by virtue of being a submit button.** Labels like Generate, Apply, Run, Search, Show, and Continue usually sit on read-only handlers. Take a report setup form whose "Generate report" handler is `setReportInput(input)`. That is a read-only submit. The report body only renders once you press it, so skipping it means the changed component is never captured. Look at the handler:

   ```bash
   rg -n "generateReport|onSubmit|handleGenerate" src/views/reports/   # then read the handler body
   ```

   Mutate is the classification for `useMutation`, `client.mutate`, and `gql` tags containing `mutation` **reached by the trigger's own handler**. A mutation elsewhere in the component you are opening does not make opening it a mutation. A history dialog that can edit rows is safe to open and screenshot, as long as you never press its save or delete. When the handler is still ambiguous after you read it, treat it as mutate and say so. Not having read it is not ambiguity.
4. Use the fixture recorded in the plan. If the trigger targets a data entity, such as a row's edit dialog or an item's detail panel, both sessions MUST open it on the **same entity**, the same row, id, and name. For data-gated states that is the fixture resolved in section 2 step 4. Otherwise pick deterministically: the first row under a stable sort, or a named fixture present in both environments. Diffing dialogs opened on different entities produces pure noise, not a comparison.
5. Perform the interaction on X and Y. Apply the fixture selection first, meaning the line, product, group, or entity, then the trigger. Identical in both sessions, in the same order.
6. Readiness-gate the revealed state in both sessions independently. The full gate from step (b) applies to dialog and tab content just as it does to page loads, since dialogs frequently lazy-load their data after opening.
7. Confirm the target component actually rendered, in both sessions, before screenshotting. The interaction succeeding is not evidence that the component is on screen. Find its own markup in the snapshot, the dialog title or the card or the table, not merely the container that should hold it. If you instead find an empty state, a "no data" message, or a bare container, **the fixture is wrong, not the path**. Go back to section 2 step 4, pick another candidate, and retry. Screenshotting the empty state and calling the path covered is worse than skipping it. It counts as coverage in the report and shows the reviewer nothing about the change.
8. Screenshot both. Name them with the interaction descriptor, `<route>_<component>-open.png`, for example `reports_export-dialog-open.png`, and record the render path down to the opened element: `(/reports) ReportsPage > ExportDialog`.
9. Reset. Restore the default state in both sessions before the next trigger: close the dialog with its close button or Escape, switch back to the default tab, or re-navigate to the route, with the token, per the direct-navigation rule in step a. Never let state leak from one capture into the next.

**Depth cap:** traverse at most **two interaction levels** below the page, for example page, then dialog, then a tab inside that dialog. Deeper states, such as a nested confirm inside a dialog's tab, are out of scope. Record them as `not traversed (depth cap)` in the report rather than capturing them ad hoc.

The cap counts hops that **reveal new state**. Getting to the state does not count against it. Navigating in via a producing control, and selecting the fixture that makes the component exist, are the cost of reaching the page at all. A line picker, then a product picker, then the card that renders is one level, not three. Do not let the cap become the reason a data-gated component goes uncaptured. That is the depth cap laundering a fixture search you did not do.

#### e. Priority 2: Mixpanel-tracked components (critical paths)

Components that fire Mixpanel track events are the **"hot" activity components**. They represent user interactions that affect all end users and are the most critical paths to screenshot and compare after the diff-affected routes. They take priority over general route discovery.

How to discover Mixpanel-tracked components:

1. Search the application source for Mixpanel tracking calls. Common patterns:
   - `mixpanel.track(` and `Mixpanel.track(`
   - `track(` calls from a shared analytics or tracking module
   - `useTracking()` and `useAnalytics()` hooks that wrap Mixpanel
   - String literals that look like event names passed to a tracking function: `"Button Clicked"`, `"Page Viewed"`, `"Feature Used"`
2. For each tracked component, identify:
   - Which route renders it. Trace the component's import chain back to a page or route.
   - What user interaction triggers the event: a button click, form submission, toggle, tab switch.
   - The event name. Record it for the report.
3. Build a Mixpanel coverage list mapping event name, route, component, and the interaction needed.

Screenshot strategy for tracked components:

- Navigate to the route that renders the tracked component.
- Screenshot the page in its default state.
- If an interaction triggers the tracked event, such as clicking a button, opening a modal, or expanding a section, perform that interaction and take a **second screenshot** of the resulting state. Name it with a descriptor: `<route>_after-<interaction>.png`.
- Do this on both X and Y sessions so the diff catches any visual changes to these critical paths.

**CRITICAL: do NOT actually trigger Mixpanel events.** The goal is to screenshot the components and their surrounding UI, not to fire analytics. If the tracked interaction would cause a side effect, a GraphQL mutation, form submission, or an API call beyond navigation, screenshot only the pre-interaction state and note in the report that the interaction was skipped.

#### f. Priority 3: general route discovery and navigation

After all diff-affected and Mixpanel-tracked places are covered, discover and test the remaining routes:

**CRITICAL: navigate from `/`, do not construct URLs manually.** Many routes require query parameters with page-specific identifiers, such as `/reports?id=abc123` or `/devices/xyz`. You cannot guess these identifiers. Start from the root URL (`/`) and discover pages by following links in the UI. That way you visit routes with the correct parameters the application itself provides.

**CRITICAL: trailing slash sensitivity.** Routes may be sensitive to the presence or absence of a trailing `/`. Before navigating, check the application's `next.config.js`, or equivalent, for a `trailingSlash` setting:
- With `trailingSlash: true`, all routes must end with `/`, as in `/dashboard/`
- With `trailingSlash: false`, or unset, routes must NOT end with `/`, as in `/dashboard`

The wrong format causes 404s or redirects. Match the convention the application uses.

Routes are reached through two mechanisms. Both are first-class and both must be exercised during traversal:

1. Anchor and link elements (`<a href="...">`), discovered via browser snapshots.
2. onClick handlers that trigger client-side router changes, discovered by reading the source of the application under test.

Prefer performing the actual in-app click over re-opening the discovered URL directly. It preserves the in-app session and matches real user behavior. If a direct URL open is unavoidable, or the anchor causes a full page load, the token rule from step (a) applies: always append `token=<api-key>`.

**CRITICAL: avoid any onClick handler that fires a GraphQL mutation.** Before clicking an element with an onClick handler, check the source to confirm the handler performs a route or navigation change (`history.push`, `navigate()`, `router.push`, a Next.js `Link`), a local state change, or a query, and does NOT trigger a GraphQL mutation (`useMutation`, `client.mutate`, `gql` tags with `mutation`). This is the same three-way classification as Priority 1.5 step 3, and the same caution applies to reading it. "In doubt" means you read the handler and could not tell, not that you did not read it. When in doubt, do not click. Skip it and note it in the report.

How to discover navigatable routes:

1. Read the application's router configuration in the source, such as React Router `<Route>` definitions, the Next.js `pages/` or `app/` directory, or a Vue Router config, to build a full route map.
2. Cross-reference the browser snapshot to identify clickable elements that navigate between routes.
3. For onClick-based navigation, trace the handler in source to confirm it is a route change, not a mutation.

#### g. Functional equality checks

Functional equality means interactions produce equivalent outcomes in both environments:

1. Snapshot interactive elements on both:
   ```bash
   agent-browser --session x snapshot -i --json
   agent-browser --session y snapshot -i --json
   ```
2. Compare the interactive element sets. The same buttons, links, inputs, selects, and checkboxes should exist in both. Report any element present in one but missing in the other.
3. Navigate all discovered routes. Every internal link and safe onClick navigation target should be reachable in both environments. If a route works in X but errors in Y, or the reverse, flag it.
4. Test interactive elements. For forms, dropdowns, toggles, and other non-mutation interactive elements, perform the same interaction sequence on both and verify the resulting state is equivalent: same snapshot structure, same navigation outcome. Screenshot after each significant interaction.
5. List skipped elements: any onClick handlers skipped because they trigger GraphQL mutations or could not be confirmed as safe navigation.

#### h. Ensure matching screenshot resolutions

Before diffing, both screenshots for a given route **must** have the same pixel dimensions. Check first:

```bash
x_size=$(magick identify -format "%wx%h" .visual-comparison/x/<route>.png)
y_size=$(magick identify -format "%wx%h" .visual-comparison/y/<route>.png)
```

Interpret a mismatch by dimension. They mean different things:

- **Check both widths against the agreed width, not only against each other.** `xw == yw` is necessary, not sufficient; `xw == yw == agreed` is the invariant. Equal-but-wrong is the case that slips through: two captures that both come out 1921 on an agreed 1920 match each other and read as clean.
  - **Widths differ from each other: viewport mismatch. Never pad.** The two sessions were not at the same resolution (see the invariant in "Viewport and screen size"), so the renders are not comparable at all. Re-apply the viewport to **both** sessions, re-take **both** screenshots, and only then diff.
  - **Widths agree with each other but not with the agreed width:** the viewport is fine and the page overflows horizontally. The pair is comparable, but say so in the report instead of letting the row read as clean.
- **Differing heights at the same width are a legitimate content-height difference** in full-page captures, for example one environment rendering an extra row. That is comparable. Pad the shorter image's canvas with white at the bottom so the diff tool accepts them, and note that the height itself differed. It is often a finding in its own right, not noise:

```bash
magick .visual-comparison/x/<route>.png -background white -gravity NorthWest -extent <width>x<max_height> .visual-comparison/x/<route>.png
magick .visual-comparison/y/<route>.png -background white -gravity NorthWest -extent <width>x<max_height> .visual-comparison/y/<route>.png
```

Use the shared width and the maximum of the two heights as the target dimensions.

#### i. Mask watermarks and dev server indicators

Development servers, Next.js among them, often render floating indicators, watermarks, or build-status badges that are not part of the application UI. Exclude them from the diff to avoid false positives.

Common indicators to mask:
- The Next.js dev indicator, a floating element in the bottom-right corner
- Vercel and Turbopack build badges
- Hot-reload status overlays
- Any framework watermark or "development mode" banner

Masking procedure:
1. Identify the bounding box of the indicator by inspecting the screenshot or the DOM, looking for selectors like `[data-nextjs-toast]` or `nextjs-portal`.
2. Draw a filled white rectangle over that region on **both** X and Y screenshots before diffing:

```bash
magick .visual-comparison/x/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" .visual-comparison/x/<route>.png
magick .visual-comparison/y/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" .visual-comparison/y/<route>.png
```

If you cannot determine the exact bounding box, mask a conservative region in the corner where the indicator appears, such as the bottom-right 300x80px.

#### j. Visual equality checks and the threshold-based verdict

Each screenshot pair gets exactly one verdict: **good**, assumed equal, not a finding, nothing uploaded, or **substantial**, a real change someone should address. A flat differing-pixel percentage is a poor gate on its own. A changed button label touches about 0.03% of pixels while an invisible one-level background shift touches 100%. So the gate combines noise suppression with spatial clustering: scattered anti-aliasing speckle passes, one contiguous changed region fails.

1. Build the changed-pixel mask and total percentage. Take the per-channel max difference, NOT a grayscale conversion, which applies Rec.709 luma weights and heavily discounts pure-blue changes, then blur and morphologically open to kill sub-pixel and text anti-aliasing noise:

   ```bash
   magick .visual-comparison/x/<route>.png .visual-comparison/y/<route>.png \
     -alpha off -compose difference -composite \
     -separate -evaluate-sequence Max \
     -blur 0x1 -threshold 10% \
     -morphology Open Disk:1 \
     .visual-comparison/diff/<route>_mask.png

   pct=$(magick .visual-comparison/diff/<route>_mask.png -format "%[fx:100*mean]" info:)
   ```

   The mean of the binarized mask IS the fraction of changed pixels. No manual division needed.

2. Cluster the mask. Gate on contiguous regions, not scattered counts:

   ```bash
   magick .visual-comparison/diff/<route>_mask.png \
     -define connected-components:verbose=true \
     -define connected-components:area-threshold=40 \
     -connected-components 8 null:
   ```

   This prints area and bounding box per changed blob. Take the largest non-background blob. Its bounding box also tells you *where* the change is, which feeds the diff summary.

3. Verdict:
   - A largest contiguous changed region of **1600 px** or more, roughly 40x40, OR a total changed fraction of **0.2%** or more, is **substantial**.
   - Anything else is **good**. Equality is assumed. Record the render path as good, with its percentage, and move on. Do not report sub-threshold pixel counts as findings. That is exactly the noise this gate exists to remove. Good pairs still get their before and after published, collapsed, per step 7. The verdict decides prominence, not whether a reviewer can see the page.

   Thresholds are the defaults from Inputs. Use the user's overrides if given.

4. For substantial verdicts only, produce the human-facing artifacts:
   - A red-highlight diff image. Note that `compare` writes its metric to stderr and exits 1 when images differ, which trips `set -e`, so guard it:
     ```bash
     magick compare -fuzz 10% -highlight-color red -lowlight-color white \
       .visual-comparison/x/<route>.png .visual-comparison/y/<route>.png \
       .visual-comparison/diff/<route>.png 2>/dev/null || true
     ```
   - A **one-line diff summary**. Map the largest blob's bounding box back to the component under it, via the snapshot and the render path, and describe what changed: "FilterPanel apply-button row shifted ~4px down; button color changed". This summary is what appears in the verdict tables.

5. Volatile regions: extend the masking from step (i) to known-volatile content, such as timestamps, relative times ("2 minutes ago"), avatars, live-updating charts, and animation frames, by compositing white over those areas on **both** images before step 1. List every masked region in the report so reviewers know what was excluded.

Full-page screenshots stay in `.visual-comparison/x/` and `.visual-comparison/y/`, masks and diff images in `.visual-comparison/diff/`.

### 4. Development server error detection and resolution

While navigating, watch for **non-crash errors** that keep pages from rendering correctly. These differ from full server crashes: the server is still running but the page cannot be displayed. Common examples:

- Module import errors: `Module not found: Can't resolve '...'`, `SyntaxError: Cannot use import statement outside a module`, `TypeError: X is not a module`
- Compilation and build errors: TypeScript errors, Webpack or Vite build failures shown as error overlays
- Runtime errors that produce an error overlay: React error boundaries showing a stack trace, Next.js error pages with stack traces
- Missing dependency errors: `Cannot find module 'foo'`

These indicate a fixable problem in the source code, **not** an infrastructure or server problem.

#### When a development server error is detected

1. Halt the comparison immediately. Do not continue testing other routes. The error may affect multiple pages.
2. Diagnose the root cause by reading the error message, stack trace, and relevant source files.
3. Fix the underlying problem in the source. The fix must be minimal and scoped only to resolving the error. Do not make any changes related to the main work at hand.
4. Commit the fix to a separate branch:
   - Create a new branch from the current branch, such as `fix/visual-comparison-<short-description>`.
   - Commit only the error-fix changes to that branch.
   - Push the branch.
   - Switch back to the original branch and merge the fix branch into it, or rebase on top of it, so the comparison can proceed with the fix applied.
5. Resume the visual comparison from the beginning, since the fix may affect previously tested routes.

That way:
- Error fixes are **not mixed** into the PR's main work. They live on their own branch and can be reviewed and merged independently.
- The visual comparison runs **on top of** the fixes, giving accurate results.

**Important:** this applies only to the **Y, comparison or development, environment**. If the X baseline shows errors, report them to the user and wait. Baseline errors are not yours to fix.

### 5. Crash detection and recovery

While navigating and interacting, watch for:

- Pages returning HTTP 5xx errors
- Blank pages where content is expected
- Browser errors visible via `agent-browser errors`
- Connection refused or timeout on navigation

When a crash is detected:

- User-started server: stop testing. Report which environment crashed, on which route, and what error you saw. Wait for the user to say continue.
- Skill-started server: restart the server, wait for it to become healthy, then resume from the route that triggered the crash.

Before resuming after **any** recovery (server restart, browser session re-open, token rotation), re-run the session warm-up with the token and re-apply the viewport to **both** sessions. The resolution invariant from "Viewport and screen size" must hold across restarts.

### 6. Report

After all routes are tested, **reconcile the plan against what was actually captured before writing anything**. Take the tracer's breadcrumb list from section 2 and check off each one against the files in `.visual-comparison/x/`. Every planned breadcrumb must appear in the reconciliation table below with either a screenshot or a reason from the evidence table in "Dropping a traced path requires evidence". A planned path simply absent from the report is a defect in the run, not an omission in the write-up.

**Reconciliation is a gate, not a formality.** Its normal outcome when rows are missing is that you go back into capture, not that you write them up as gaps. Before the report can be written, every ❌ row must pass all three checks:

1. Its reason is one of the five in the evidence table. `not captured (search incomplete)` is not one of them. It means the run is unfinished (see "Dropping a traced path requires evidence").
2. Its evidence exists and is specific: the handler source for `skipped (mutation)`, the HTTP status for `blocked`, the searched candidate set for `unreachable (no qualifying fixture)`.
3. The evidence was produced **before** capture, in the plan, not reconstructed now to justify a gap.

Then re-read each drop reason before publishing it. If the reason is a claim about the app ("not reachable from the UI", "no such trigger exists", "requires data we do not have"), confirm it against the producer or fixture search rather than against your recollection of why you moved on at the time. Reasons written mid-run under time pressure are exactly the ones that turn out to be wrong. If one is wrong, correct it and queue the missing capture. If the false reason was already published in a PR comment or verification draft, correct that too rather than leaving it standing.

A run that ends with several ❌ rows and no substantial per-path findings behind them has usually mis-scoped the *capture* phase, not discovered a hard boundary in the app. Check that before publishing: the modal, tab, and data-gated states are where a change to shared data plumbing shows up differently from the default page, so they are the rows a reviewer most needs and the ones cheapest to quietly drop.

Then produce a summary:

```markdown
## Visual comparison report

### Coverage plan reconciliation
| Planned render path | Captured | Reason if not |
|---|---|---|
| (/dashboard) DashboardPage | ✅ | |
| (/dashboard) DashboardPage ▸ [click "Export"] ExportDialog | ✅ | |
| (/dashboard/shift-group) DashboardGroupShift ▸ GroupShiftDashboard | ✅ | fixture: group "Packaging AM", entered via group sidebar (`dashboard-menu.tsx:88`) |
| (/reports) ReportsPage ▸ DeleteConfirm | ❌ | skipped (mutation). Handler calls `useMutation(DELETE_REPORT)` |
| (/insights/golden-batch) GoldenBatchPage ▸ GoldenBatchCard | ❌ | unreachable (no qualifying fixture). Needs a (line, product) pair with a current or pending golden batch; queried `goldenBatch` for all 14 lines × their products, none returned one |

### Comparison verdicts
Every ✅ and ⚠️ row here must carry a local X and Y screenshot path. Those become the image cells in the PR comment's table (step 7), so a row without them cannot be published.

| Render path | Coverage reason | Verdict | X / Y files |
|---|---|---|---|
| (/home) HomePage | discovery | ✅ 0.0002% | x/home.png, y/home.png |
| (/dashboard) DashboardPage | diff: src/styles/button.css | ✅ 0.0000% | x/dashboard.png, y/dashboard.png |
| (/dashboard) DashboardPage > FilterPanel | diff: src/components/FilterPanel.tsx | ⚠️ 0.84%. Apply-button row shifted ~4px, button color changed | x/dashboard_filter-open.png, y/dashboard_filter-open.png |
| (/dashboard) DashboardPage > ExportButton | Mixpanel "Export Clicked" | skipped (mutation), pre-interaction state only | n/a |

### Mixpanel-tracked components (critical paths)
| Event name | Render path | Interaction | Verdict |
|---|---|---|---|
| "Dashboard Viewed" | (/dashboard) DashboardPage | page load | ✅ good |
| "Filter Applied" | (/dashboard) DashboardPage > FilterPanel | click "Apply" | ⚠️ substantial, see verdict table |
| "Export Clicked" | (/dashboard) DashboardPage > ExportButton | skipped (mutation) | n/a |
- ...or "No Mixpanel track events found in source"

### Additional routes tested
- /home
- /settings/profile
...

### Functional differences
- [ ] /dashboard: button "Export CSV" present in X but missing in Y
- ...or "None found"

### Substantial visual differences
- [ ] (/settings/profile) SettingsPage > ProfileForm: content container padding mismatch, largest changed region 120x800px (see `.visual-comparison/diff/settings_profile.png`)
- ...or "None. All compared render paths within thresholds (assumed equal)"

### Masked volatile regions
- (/dashboard) DashboardPage: live throughput chart (top-right 600x300px), "last updated" timestamp
- ...or "None beyond dev-server indicators"

### Routes blocked by network errors
- [ ] /devices: `GET https://api.example.com/devices` returned 503 in Y only. Page rendered an empty state, screenshot skipped. Cause: backend dependency unavailable, not investigated further.
- ...or "None"

### Authentication events
- Y: 401 and sign-in redirect on first load of `/`, resolved by one re-navigation with the token. Token-to-session race, not expiry
- X: token expired mid-session on /reports, rotated via `fbctl user assume`, resumed from /reports
- ...or "None"

### Development server errors fixed
- Y: `Module not found: Can't resolve './Foo'` on /dashboard, fixed in branch `fix/visual-comparison-missing-foo-import` (commit abc1234)
- ...or "None"

### Crashes encountered
- Y crashed on /dashboard (restarted automatically / waited for user)
- ...or "None"

### Screenshots
All screenshots saved to `.visual-comparison/x/` and `.visual-comparison/y/`, diff images in `.visual-comparison/diff/`
```

### 7. Upload before and after comparisons to the PR

After producing the report, post the comparison as a PR comment. The upload, embed, and post mechanics belong to the **gh-image-upload** skill: tooling availability, session-token authentication including headless `GH_SESSION_TOKEN` handling and expiry recovery, `gh image` usage, and posting via `gh pr comment`. Use it for this step.

Because of the setup-time preflight, a missing token at this point is not an expected state. If the upload nevertheless fails on auth, because the session was invalidated mid-run, follow gh-image-upload's expiry recovery: ask the user for a fresh token and retry, rather than silently downgrading to a text-only comment. Skip uploads only if the user declined them at preflight, or declines now. In that case keep the local `.visual-comparison/` artifacts and note in the report that the PR comment was posted without images, or not posted, and why.

What is specific to this skill:

1. **The verdict table carries the screenshots. They are columns in it, not a section below it.** Every row that was compared shows its own X and Y image inline, next to its render path and its percentage. The pixel verdict is the summary and the screenshots are the proof, so they belong in the same row. A reviewer scanning the table sees both sides of every path at once, including the ones the gate called good. That is how they catch a real difference the thresholds missed, a chart the mask hid, or a fixture that rendered an empty state. A verdict with no image beside it is an assertion, not evidence.

   | Verdict | X and Y columns | Extra below the table |
   |---|---|---|
   | ⚠️ substantial | both images, embedded | full-width pair, zoom crop, diff overlay |
   | ✅ good | both images, embedded | none |
   | ⛔ blocked / skipped / ⬜ not captured | empty cells, there is nothing to show | none |

   **Embed the images, never link them.** Every image cell is `![alt](url)`. A bare `[alt](url)` renders as a link, which makes the reviewer open ten tabs to do what the table was supposed to do for them. If a cell in your draft starts with `[` and not `![`, it is wrong.

   **The threshold gate decides what gets a section, not what gets pictures. Do not curate.** Image cells are filled for every compared path, never chosen by which screenshots look most interesting, most chart-heavy, or most worth a reviewer's time. Trimming the published set to a tidier handful hides coverage you actually have, and a reviewer counting images will conclude you never captured the missing ones. If that is a large number of uploads, that is the correct shape of a thorough run. Pass every file to a single `gh image` invocation rather than one call per screenshot, and map the returned URLs back to render paths in capture order.
2. Comment structure. One table, every compared path in it with its pair. Substantial paths repeat below at full width, where the change is actually legible:

   ```markdown
   ## Visual comparison: <X label> vs <Y label>

   Viewport 1920x1080, <N> render paths compared, <M> substantial, <K> not captured.

   | Render path | Verdict | X (before) | Y (after) |
   |---|---|---|---|
   | `(/) Lines ▸ LineCard ▸ Chart` | ⚠️ 1.56%, largest region 88x95px | ![lines-x](…) | ![lines-y](…) |
   | `(/sensors) … ▸ SensorCard` | ⚠️ 1.06%, tick labels shifted ~4px | ![sensors-x](…) | ![sensors-y](…) |
   | `(/line?tab=live) LiveViewPage` @ 1W | ✅ 0.07% | ![live-1w-x](…) | ![live-1w-y](…) |
   | `(/dashboard/batch) BatchDashboardContent` | ✅ 0.0000% | ![batch-x](…) | ![batch-y](…) |
   | `(/operator) OperatorView` | ✅ 0.0000% | ![operator-x](…) | ![operator-y](…) |
   | `(/reports) ReportsPage ▸ ExportDialog` | ⛔ blocked, API 503 in Y | | |
   | `… ▸ EditCountDialog` | skipped (mutation) | | |
   | `(/insights/golden-batch) … ▸ GoldenBatchCard` | ⬜ not captured, no line/product pair has a golden batch | | |

   ### `(/) Lines ▸ LineCard ▸ Chart`, 1.56%
   Trace deviates up to 12px per point, axis ticks shifted. Largest changed region 88x95px.

   Zoomed on the changed region, X left, Y right:

   | X | Y |
   |---|---|
   | ![lines-crop-x](…) | ![lines-crop-y](…) |

   <details><summary>Full page and diff overlay</summary>

   | X, legacy | Y, samplesV2 |
   |---|---|
   | ![lines-full-x](…) | ![lines-full-y](…) |

   ![lines-diff](…)
   </details>

   _Masked from every diff: dev-server indicator, live throughput chart._
   ```

   Verdict column values: `✅` good with its percentage, `⚠️` substantial with its percentage and the one-line diff summary, `⛔` or `skipped` for blocked or mutation-skipped paths with the reason, `⬜` planned but not captured with the reason. **The percentage appears on good rows too.** `✅ 0.0000%` and `✅ 0.11%` say different things to a reviewer, and a bare checkmark throws that away. The `⬜` rows come straight from the reconciliation table, and per that section they should be rare and evidenced. A gap the reviewer can see is recoverable, one you quietly dropped is not.

   Keep image alt text keyed to the render path, `<route>-<component>-x` and `-y`, so a reviewer reading the raw markdown can still tell which pair is which.

   In-table images render as thumbnails scaled to the column, which is what makes the table scannable. The reviewer clicks through for detail. That is also why substantial paths repeat below at full width with a crop: the thumbnail proves the page rendered, the crop shows the finding.
3. **Check the table before posting.** Count the rows whose verdict is ✅ or ⚠️, and count the filled image cells. The second number must be exactly twice the first. If it is not, you either dropped a pair or left a row unfilled, and the comment is not ready. Then check that every image cell starts with `![`.

   A re-run does not get to shrink this. Adding a run-over-run column, or a table comparing this run's percentages against the last one's, is useful context and belongs in the comment. It **replaces nothing**. The per-path table with its image pairs is the deliverable, and a second run that posts percentage deltas instead of screenshots has published less than the first run did while looking like progress.
4. **Crop where a full-page screenshot cannot show the difference.** Some substantial changes are small or dense: a shifted axis, a few pixels of trace deviation, a line-weight change. For those, upload a zoomed crop of the changed region on both sides and lead the path's section with it, keeping the full pair below in the `<details>`. Take the crop box from the largest blob's bounding box in step (j.2), pad it, and apply the **same** box to X and Y:

   ```bash
   magick .visual-comparison/x/<route>.png -crop <w>x<h>+<x>+<y> +repage .visual-comparison/diff/<route>_crop-x.png
   magick .visual-comparison/y/<route>.png -crop <w>x<h>+<x>+<y> +repage .visual-comparison/diff/<route>_crop-y.png
   ```

   A reviewer scanning a 1920x3000 page render will not find a 4px tick shift on their own. The crop is what makes the finding checkable; the full pair stays for context.
5. Include the posted comment URL in the final report to the user.

## Notes for PR reviewers

The `.visual-comparison/` directory is ephemeral documentation. Screenshots give a quick visual diff for reviewers who want to verify UI changes without running both environments locally, and the before/after comment posted via `gh image` is the durable, PR-facing copy. The local directory can be cleaned up after the PR is merged. Do NOT commit it unless the user explicitly asks to.
