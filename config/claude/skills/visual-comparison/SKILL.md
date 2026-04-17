---
name: visual-comparison
description: Compares two web application environments (X and Y) across all navigatable pages for functional and visual parity, producing screenshot documentation for PR reviews
---

# Visual Comparison — X/Y Web Application Testing

Compare two web application environments to verify functional and visual parity. Produces screenshot documentation suitable for PR review.

## When to use

When the user asks to compare two web applications (e.g., "compare localhost:3000 and localhost:3001", "compare staging and production", "compare before and after").

## Inputs from the user

1. **X** — the baseline environment (URL or instructions to start it)
2. **Y** — the comparison environment (URL or instructions to start it)
3. **Pages/routes to navigate** — the user may specify routes, but by default the skill discovers critical routes by tracing Mixpanel track events in the source code (see "Priority: Mixpanel-tracked components" below)
4. **API key** (if required) — passed as a `token=<api-key>` query parameter on all requests
5. **Screen size** (optional) — viewport dimensions for screenshots (e.g., `1920x1080`, `1440x900`, `1280x720`). If the user does not specify a screen size, **ask them before starting the comparison**. Do not assume a default — different applications are designed for different viewports and the choice affects the accuracy of the comparison.

## Setup

### Screenshot output directories

Create two directories at the repository root for storing screenshots:

```
.visual-comparison/
  x/       # baseline screenshots
  y/       # comparison screenshots
  diff/    # ImageMagick diff images
```

Name screenshot files by route: `home.png`, `dashboard.png`, `settings_profile.png` (replace `/` with `_`, strip leading slash). For stateful pages (e.g., after clicking a button), append a descriptor: `dashboard_after-filter-apply.png`.

### Server management

- **User-started servers**: If the user started the servers, do NOT restart them on crash. Instead, report the crash clearly (which environment, the error if visible) and wait for the user's explicit go-ahead before resuming testing.
- **Skill-started servers**: If you started a server as part of the comparison setup, recover from crashes by restarting it automatically, then resume testing from where it left off.

Track who started each server so you handle crashes correctly.

### Viewport / screen size

Set the browser viewport on both sessions before taking any screenshots:

```bash
agent-browser --session x resize <width> <height>
agent-browser --session y resize <width> <height>
```

Use the dimensions provided by the user. If the user did not specify a screen size, **you must ask them before proceeding**. Suggest a few common options (e.g., 1920x1080, 1440x900, 1280x720) but let them choose.

### Authentication

If the user provides an API key, append `?token=<api-key>` to every URL when navigating (or `&token=<api-key>` if the URL already has query parameters). The API key applies to both X and Y environments.

**Key rotation**: If any request returns a 401/403 Unauthorized response, or the browser is redirected to a login/auth-error page, or the application shows an "unauthenticated"/"session expired" message:

1. Stop testing immediately.
2. Report which environment and route triggered the auth failure.
3. Ask the user for a new API key.
4. Once provided, substitute the new key into all subsequent URLs and resume testing from the route that failed.

## Procedure

### 1. Verify both environments are reachable

```bash
agent-browser --session x open <X_URL>
agent-browser --session y open <Y_URL>
```

If either fails to load, report it. Follow the crash-handling rules above.

### 2. For each route specified by the user

Perform the following on both X and Y using separate browser sessions (`--session x` / `--session y`):

#### a. Navigate

```bash
agent-browser --session x open "<X_URL>/<route>?token=<api-key>"
agent-browser --session x wait --load networkidle
agent-browser --session y open "<Y_URL>/<route>?token=<api-key>"
agent-browser --session y wait --load networkidle
```

If no API key was provided, omit the `token` query parameter.

#### b. Wait for loading indicators to finish

After navigation and `networkidle`, the page may still show loading indicators (spinners, skeleton screens, progress bars, shimmer effects, etc.). Before taking any screenshot, wait for these to disappear:

1. **Take a snapshot** to inspect the current page state:
   ```bash
   agent-browser --session x snapshot --json
   ```
2. **Look for loading indicators** in the snapshot — common patterns include:
   - Elements with roles like `progressbar`, `status`, or `alert` containing "loading" text
   - Skeleton/placeholder elements (CSS classes like `skeleton`, `shimmer`, `placeholder`, `loading`)
   - Spinner elements (`spinner`, `loader`, `loading-indicator`)
   - Aria attributes: `aria-busy="true"`, `aria-label="Loading"`
3. **If loading indicators are present**, wait briefly and re-check:
   ```bash
   agent-browser --session x wait --timeout 2000
   agent-browser --session x snapshot --json
   ```
   Repeat until loading indicators are gone or a reasonable timeout is reached (max ~15 seconds). If indicators persist beyond the timeout, proceed with the screenshot and note it in the report.
4. **Do this for both sessions** (X and Y) independently — they may load at different speeds.

#### c. Screenshot — initial page load

```bash
agent-browser --session x screenshot --full .visual-comparison/x/<route_name>.png
agent-browser --session y screenshot --full .visual-comparison/y/<route_name>.png
```

#### d. Priority: Mixpanel-tracked components (critical paths)

Components that fire Mixpanel track events are **"hot" activity components** — they represent user interactions that affect all end users and are considered the most critical paths to screenshot and compare. These take priority over general route discovery.

**How to discover Mixpanel-tracked components:**

1. Search the application source code for Mixpanel tracking calls. Common patterns:
   - `mixpanel.track(` / `Mixpanel.track(`
   - `track(` calls from a shared analytics/tracking module
   - `useTracking()` / `useAnalytics()` hooks that wrap Mixpanel
   - String literals that look like event names passed to a tracking function (e.g., `"Button Clicked"`, `"Page Viewed"`, `"Feature Used"`)
2. For each tracked component, identify:
   - **Which route renders it** — trace the component's import chain back to a page/route.
   - **What user interaction triggers the event** — a button click, form submission, toggle, tab switch, etc.
   - **The event name** — record this for the report.
3. Build a **Mixpanel coverage list**: a mapping of `event name → route → component → interaction needed`.

**Screenshot strategy for tracked components:**

- Navigate to the route that renders the tracked component.
- Screenshot the page in its default state.
- If the tracked event is triggered by an interaction (e.g., clicking a button, opening a modal, expanding a section), perform that interaction and take a **second screenshot** showing the resulting state. Name it with a descriptor: `<route>_after-<interaction>.png`.
- Do this on both X and Y sessions so the diff captures any visual changes to these critical paths.

**CRITICAL: Do NOT actually trigger Mixpanel events.** The goal is to screenshot the components and their surrounding UI, not to fire analytics. If the tracked interaction would cause a side effect (GraphQL mutation, form submission, API call beyond navigation), screenshot only the pre-interaction state and note in the report that the interaction was skipped.

#### e. General route discovery and navigation

After all Mixpanel-tracked components have been covered, discover and test remaining routes:

Routes are reached through two mechanisms:

1. **Anchor/link elements** (`<a href="...">`) — discovered via browser snapshots.
2. **onClick handlers that trigger client-side router changes** — discovered by reading the source code of the application under test.

**CRITICAL: Avoid any onClick handler that fires a GraphQL mutation.** Before clicking an element with an onClick handler, check the source code to confirm the handler performs a route/navigation change (e.g., `history.push`, `navigate()`, `router.push`, Next.js `Link`) and does NOT trigger a GraphQL mutation (`useMutation`, `client.mutate`, `gql` tags with `mutation`). When in doubt, do not click — skip and note it in the report.

**How to discover navigatable routes:**

1. Read the application's router configuration in the source code (e.g., React Router `<Route>` definitions, Next.js `pages/`/`app/` directory, Vue Router config) to build a full route map.
2. Cross-reference with the browser snapshot to identify clickable elements that navigate between routes.
3. For onClick-based navigation, trace the handler in source to confirm it is a route change, not a mutation.

#### f. Functional equality checks

Functional equality means interactions produce equivalent outcomes in both environments:

1. **Snapshot interactive elements** on both:
   ```bash
   agent-browser --session x snapshot -i --json
   agent-browser --session y snapshot -i --json
   ```
2. **Compare the interactive element sets**: same buttons, links, inputs, selects, checkboxes should exist in both. Report any elements present in one but missing in the other.
3. **Navigate all discovered routes**: every internal link and safe onClick navigation target should be reachable in both environments. If a route works in X but errors in Y (or vice versa), flag it.
4. **Test interactive elements**: for forms, dropdowns, toggles, and other non-mutation interactive elements — perform the same interaction sequence on both and verify the resulting state is equivalent (same snapshot structure, same navigation outcome). Screenshot after each significant interaction.
5. **Skipped elements**: list any onClick handlers that were skipped because they trigger GraphQL mutations or could not be confirmed as safe navigation.

#### g. Ensure matching screenshot resolutions

Before diffing, both screenshots for a given route **must** have the same pixel dimensions. If they differ (e.g., due to different full-page scroll heights), resize the shorter image's canvas to match the taller one by padding with white at the bottom:

```bash
# Get dimensions
x_size=$(magick identify -format "%wx%h" .visual-comparison/x/<route>.png)
y_size=$(magick identify -format "%wx%h" .visual-comparison/y/<route>.png)

# If heights differ, extend the shorter one
magick .visual-comparison/x/<route>.png -background white -gravity NorthWest -extent <target_width>x<target_height> .visual-comparison/x/<route>.png
magick .visual-comparison/y/<route>.png -background white -gravity NorthWest -extent <target_width>x<target_height> .visual-comparison/y/<route>.png
```

Use the maximum width and maximum height from the two images as the target dimensions.

#### h. Mask watermarks and dev server indicators

Development servers (e.g., Next.js) often render floating indicators, watermarks, or build-status badges that are not part of the application UI. These must be excluded from the diff to avoid false positives.

**Common indicators to mask:**
- Next.js dev indicator (bottom-right corner floating element)
- Vercel/Turbopack build badges
- Hot-reload status overlays
- Any framework watermark or "development mode" banner

**Masking procedure:**
1. Identify the bounding box of the indicator by inspecting the screenshot or the DOM (e.g., `[data-nextjs-toast]`, `nextjs-portal`, or similar selectors).
2. Draw a filled white rectangle over that region on **both** X and Y screenshots before diffing:

```bash
magick .visual-comparison/x/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" .visual-comparison/x/<route>.png
magick .visual-comparison/y/<route>.png -fill white -draw "rectangle <x1>,<y1> <x2>,<y2>" .visual-comparison/y/<route>.png
```

If you cannot determine the exact bounding box, mask a conservative region in the corner where the indicator appears (e.g., bottom-right 300x80px).

#### i. Visual equality checks — ImageMagick diff

Visual equality means the rendered output is pixel-identical (minus masked regions) between X and Y:

1. **Generate a diff image** for each route using ImageMagick:

```bash
magick compare -metric AE -fuzz 5% \
  .visual-comparison/x/<route>.png \
  .visual-comparison/y/<route>.png \
  .visual-comparison/diff/<route>.png 2>&1
```

This outputs the number of differing pixels to stderr and writes a visual diff image highlighting differences in red. A `-fuzz 5%` tolerance accounts for sub-pixel rendering differences across environments.

2. **Interpret the result:**
   - `0` differing pixels → visual parity confirmed for this route.
   - Non-zero → inspect the diff image (`.visual-comparison/diff/<route>.png`) to determine if the differences are meaningful layout/content changes or just rendering noise.

3. **Full-page screenshots** are kept in `.visual-comparison/x/` and `.visual-comparison/y/` for human review. Diff images go into `.visual-comparison/diff/`.

4. Report any meaningful visible differences in spacing, alignment, or layout, referencing the diff image.

### 3. Development server error detection and resolution

While navigating, watch for **non-crash errors** that prevent pages from rendering correctly. These are distinct from full server crashes — the server is still running but the page cannot be displayed. Common examples:

- **Module import errors** — e.g., `Module not found: Can't resolve '...'`, `SyntaxError: Cannot use import statement outside a module`, `TypeError: X is not a module`
- **Compilation/build errors** — e.g., TypeScript errors, Webpack/Vite build failures shown as error overlays
- **Runtime errors that produce an error overlay** — e.g., React error boundaries showing a stack trace, Next.js error pages with stack traces
- **Missing dependency errors** — e.g., `Cannot find module 'foo'`

These errors indicate a fixable problem in the source code, **not** an infrastructure or server issue.

#### When a development server error is detected:

1. **Halt the comparison immediately.** Do not continue testing other routes — the error may affect multiple pages.
2. **Diagnose the root cause** by reading the error message, stack trace, and relevant source files.
3. **Fix the underlying issue** in the source code. The fix must be minimal and scoped only to resolving the error — do not make any changes related to the main work at hand.
4. **Commit the fix to a separate branch:**
   - Create a new branch from the current branch (e.g., `fix/visual-comparison-<short-description>`).
   - Commit only the error-fix changes to that branch.
   - Push the branch.
   - Switch back to the original branch and merge the fix branch into it (or rebase on top of it) so the comparison can proceed with the fix applied.
5. **Resume the visual comparison** from the beginning (since the fix may affect previously-tested routes).

This ensures:
- Error fixes are **not mixed** into the PR's main work — they live on their own branch and can be reviewed/merged independently.
- The visual comparison runs **on top of** the fixes, giving accurate results.

**Important:** This only applies to the **Y (comparison/development) environment**. If the X (baseline) environment shows errors, report them to the user and wait — baseline errors are not yours to fix.

### 4. Crash detection and recovery

While navigating and interacting, watch for:

- Pages returning HTTP 5xx errors
- Blank pages where content is expected
- Browser errors visible via `agent-browser errors`
- Connection refused / timeout on navigation

When a crash is detected:

- **User-started server**: Stop testing. Report which environment crashed, on which route, and what error was observed. Wait for the user to say to continue.
- **Skill-started server**: Restart the server, wait for it to become healthy, then resume from the route that triggered the crash.

### 5. Report

After all routes are tested, produce a summary:

```markdown
## Visual Comparison Report

### Mixpanel-tracked components (critical paths)
| Event Name | Route | Component | Interaction | Screenshot | Diff Pixels |
|---|---|---|---|---|---|
| "Dashboard Viewed" | /dashboard | DashboardPage | page load | dashboard.png | 0 |
| "Filter Applied" | /dashboard | FilterPanel | click "Apply" | dashboard_after-filter-apply.png | 342 |
| "Export Clicked" | /dashboard | ExportButton | skipped (mutation) | dashboard.png (pre-interaction only) | — |
- ...or "No Mixpanel track events found in source"

### Additional routes tested
- /home
- /settings/profile
...

### Functional differences
- [ ] /dashboard: Button "Export CSV" present in X but missing in Y
- ...or "None found"

### Visual differences
- [ ] /settings/profile: 1,247 differing pixels — content container padding mismatch (see `.visual-comparison/diff/settings_profile.png`)
- ...or "None found (0 differing pixels on all routes)"

### Development server errors fixed
- Y: `Module not found: Can't resolve './Foo'` on /dashboard — fixed in branch `fix/visual-comparison-missing-foo-import` (commit abc1234)
- ...or "None"

### Crashes encountered
- Y crashed on /dashboard (restarted automatically / waited for user)
- ...or "None"

### Screenshots
All screenshots saved to `.visual-comparison/x/` and `.visual-comparison/y/`, diff images in `.visual-comparison/diff/`
```

## Notes for PR reviewers

The `.visual-comparison/` directory is ephemeral documentation. Screenshots provide a quick visual diff for reviewers who want to verify UI changes without running both environments locally. The directory can be cleaned up after the PR is merged — do NOT commit it unless the user explicitly asks to.
