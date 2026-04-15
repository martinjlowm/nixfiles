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
3. **Pages/routes to navigate** — the user must specify which routes to test or provide a sitemap/route list
4. **API key** (if required) — passed as a `token=<api-key>` query parameter on all requests
5. **Screen size** (optional) — viewport dimensions for screenshots (e.g., `1920x1080`, `1440x900`, `1280x720`). If the user does not specify a screen size, **ask them before starting the comparison**. Do not assume a default — different applications are designed for different viewports and the choice affects the accuracy of the comparison.

## Setup

### Screenshot output directories

Create two directories at the repository root for storing screenshots:

```
.visual-comparison/
  x/       # baseline screenshots
  y/       # comparison screenshots
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

#### b. Screenshot — initial page load

```bash
agent-browser --session x screenshot --full .visual-comparison/x/<route_name>.png
agent-browser --session y screenshot --full .visual-comparison/y/<route_name>.png
```

#### c. Route discovery and navigation

Routes are reached through two mechanisms:

1. **Anchor/link elements** (`<a href="...">`) — discovered via browser snapshots.
2. **onClick handlers that trigger client-side router changes** — discovered by reading the source code of the application under test.

**CRITICAL: Avoid any onClick handler that fires a GraphQL mutation.** Before clicking an element with an onClick handler, check the source code to confirm the handler performs a route/navigation change (e.g., `history.push`, `navigate()`, `router.push`, Next.js `Link`) and does NOT trigger a GraphQL mutation (`useMutation`, `client.mutate`, `gql` tags with `mutation`). When in doubt, do not click — skip and note it in the report.

**How to discover navigatable routes:**

1. Read the application's router configuration in the source code (e.g., React Router `<Route>` definitions, Next.js `pages/`/`app/` directory, Vue Router config) to build a full route map.
2. Cross-reference with the browser snapshot to identify clickable elements that navigate between routes.
3. For onClick-based navigation, trace the handler in source to confirm it is a route change, not a mutation.

#### d. Functional equality checks

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

#### d. Visual equality checks

Visual equality means layout spacing is identical between X and Y:

1. **Compare margin and padding** on key layout elements. Use the browser console or snapshot data to verify computed styles match. Focus on:
   - Page-level containers
   - Navigation elements
   - Content sections
   - Cards, panels, modals
2. **Full-page screenshots** capture the visual state for human review. These go into the `.visual-comparison/x/` and `.visual-comparison/y/` directories.
3. Report any visible differences in spacing, alignment, or layout.

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

### Routes tested
- /home
- /dashboard
- /settings/profile
...

### Functional differences
- [ ] /dashboard: Button "Export CSV" present in X but missing in Y
- ...or "None found"

### Visual differences
- [ ] /settings/profile: Content container has 16px padding in X vs 24px in Y
- ...or "None found"

### Development server errors fixed
- Y: `Module not found: Can't resolve './Foo'` on /dashboard — fixed in branch `fix/visual-comparison-missing-foo-import` (commit abc1234)
- ...or "None"

### Crashes encountered
- Y crashed on /dashboard (restarted automatically / waited for user)
- ...or "None"

### Screenshots
All screenshots saved to `.visual-comparison/x/` and `.visual-comparison/y/`
```

## Notes for PR reviewers

The `.visual-comparison/` directory is ephemeral documentation. Screenshots provide a quick visual diff for reviewers who want to verify UI changes without running both environments locally. The directory can be cleaned up after the PR is merged — do NOT commit it unless the user explicitly asks to.
