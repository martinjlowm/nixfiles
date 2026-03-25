# Agent Instructions

## Workflow

### Phase 0: Worktree setup

1. Check if a `dependabot` worktree already exists:
   ```
   git worktree list --porcelain | grep -A2 'worktree.*dependabot$'
   ```
2. If it does **not** exist, create one:
   ```
   worktree dependabot --base origin/master
   ```
3. If it **does** exist, reuse it — `cd` into the worktree path and update it:
   ```
   cd <worktree-path>
   git fetch origin master
   git rebase origin/master
   ```
4. All subsequent work happens **inside the worktree**. State files (`.state/dependabot/`) live in the **main repo**, not the worktree — use absolute paths or `$REPO_ROOT/.state/dependabot/` when reading/writing state.

### Phase 1: Build or refresh the worklist

1. Read `$REPO_ROOT/.state/dependabot/progress.txt` for previously handled PRs and learnings
2. Check if `$REPO_ROOT/.state/dependabot/worklist.json` exists and read it
3. List all open Dependabot PRs:
   ```
   gh pr list --author "app/dependabot" --state open --json number,title,headRefName,mergeable,statusCheckRollup
   ```
4. **Create or update** `$REPO_ROOT/.state/dependabot/worklist.json` with ALL open Dependabot PRs:
   ```json
   {
     "created_at": "<ISO>",
     "updated_at": "<ISO>",
     "prs": [
       {
         "number": 123,
         "title": "PR title",
         "branch": "dependabot/npm_and_yarn/...",
         "status": "pending"
       }
     ]
   }
   ```
   - `status` is one of: `pending`, `merged`, `rebased`, `skipped`, `closed`
   - When updating: add newly opened PRs, mark merged/closed PRs accordingly, preserve status of PRs already tracked
   - Do NOT remove PRs from the list — update their status so the agent knows they were handled

### Phase 2: Review existing PRs

5. **Review PR feedback for all PRs** (even previously handled ones):
   - Fetch comments via `gh pr view <number> --comments` and `gh api repos/{owner}/{repo}/pulls/{number}/comments`
   - Address **every** unresolved comment; rebase on `origin/master` if needed; skip if PR closed
   - Fix failing CI checks (see **Troubleshooting Cancelled Workflows**; warnings aren't failures)
   - **Check CI for all PRs** — if any required check has failed or been cancelled, investigate before proceeding
   - **Check for merge conflicts on every PR**: `gh pr view <number> --json mergeable` — if `CONFLICTING`, comment `@dependabot rebase` on the PR, update status to `rebased`, and move on; if `UNKNOWN`, skip (GitHub is still computing). All PRs target `master` directly — no stacked PRs

### Phase 3: Pick and handle ONE PR

6. From `worklist.json`, pick the next PR with `status: "pending"` (oldest first). If none remain, go to the Stop Condition
7. **Check CI status**: `gh pr checks <number> --json name,state,conclusion`
   - If any check state is `PENDING`, skip this PR — set status to `skipped` with reason "CI pending", move to the Stop Condition (do NOT pick another PR)
   - If checks have failed, investigate (see **Troubleshooting Cancelled Workflows** below)
8. **Review the diff**: `gh pr diff <number>`
   - Verify the change is a straightforward dependency bump (version change in lockfile / manifest)
   - If the change looks suspicious or contains non-dependency changes, set status to `skipped` with reason noted
9. **⚠️ CRITICAL — Security audit of upgraded dependency source code:**
   This step is **mandatory** and must NOT be skipped. Evaluate the actual source code of the new dependency version from a security engineer's perspective.

   a. **Obtain the source code** — use whichever method works for the package ecosystem:
      - Clone the dependency repo at the exact new version tag into a temporary directory:
        ```
        TMPDIR=$(mktemp -d)
        git clone --depth 1 --branch <new-version-tag> <repo-url> "$TMPDIR/<package>"
        ```
      - Or download and extract the release tarball/zip:
        ```
        TMPDIR=$(mktemp -d)
        curl -sL <tarball-url> | tar xz -C "$TMPDIR"
        ```
   b. **Diff the old vs new version source** — if practical, clone both versions and diff them. Focus on:
      - New or modified install/post-install scripts (`postinstall`, `preinstall`, setup.py `cmdclass`, Makefile targets)
      - Network calls, shell/exec invocations, filesystem writes outside the package directory
      - Obfuscated code, encoded strings (base64, hex), `eval()`, dynamic `require()`/`import()` of URLs
      - Changes to authentication, cryptographic, or permission-related code
      - New native/binary dependencies or compiled artifacts that weren't present before
      - Unexpected scope expansion (a "patch" bump that adds major new capabilities)
   c. **Verdict** — record one of:
      - `PASS` — changes are consistent with the declared version bump, no suspicious patterns found
      - `FAIL` — suspicious or malicious patterns detected → set PR status to `skipped` with detailed reason, do NOT approve
      - `INCONCLUSIVE` — source is too large or complex to audit fully → set PR status to `skipped` with reason "manual security review required"
   d. **Clean up** — remove the temporary directory: `rm -rf "$TMPDIR"`
   e. **Include the verdict** in the approval comment (step 10) or skip reason

   **Do NOT approve any PR that has not passed this security audit.**

10. **Approve and merge** (only if security audit verdict is `PASS`):
   ```
   gh pr review <number> --approve --body "Dependency update looks good. CI passes. Security audit: PASS — source reviewed at <version-tag>, no suspicious changes found."
   gh pr merge <number> --squash --auto
   ```
11. Update `worklist.json`: set the PR's status to `merged` (or `skipped` if audit failed)
12. **Log the result** in `$REPO_ROOT/.state/dependabot/progress.txt` — include the security audit verdict and any findings

**1 PR = 1 task.** After completing steps 6–12 for one PR, **end the task**.

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

### Troubleshooting Cancelled Workflows

When most/all jobs show as `cancelled`, one job has a non-zero exit code — the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators) — never the root cause.

1. **Identify** the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. **Investigate** why it failed — grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```
3. If the failure is **transient** (timeout, flaky test, infrastructure): comment `@dependabot rebase` to retrigger
4. If the failure is a **real incompatibility**: set status to `skipped`, note in progress.txt why it can't be auto-merged
5. **Never** push commits to a Dependabot branch — use `@dependabot rebase` or `@dependabot recreate` instead

Fix only the identified failure; cancelled jobs and gates will pass once resolved.

**Never blindly re-trigger CI.** If a workflow was cancelled, there is always a reason. Investigate why it was cancelled first using the steps above.

**Exception — timeouts:** If a job timed out (`timed_out` conclusion), comment `@dependabot rebase` to retrigger. Timeouts are transient infrastructure issues, not code failures.

## Progress Format

Append to `$REPO_ROOT/.state/dependabot/progress.txt`:
```
## [Date] - PR #[number]
- Title: [PR title]
- Action: [merged|skipped|rebased|closed]
- Security audit: [PASS|FAIL|INCONCLUSIVE] — [brief summary of findings]
- Reason: [why, if skipped or failed]
---
```

## Stop Condition

Output `<promise>COMPLETE</promise>` when **every** PR in `worklist.json` has a status other than `pending` (i.e., all are `merged`, `rebased`, `skipped`, or `closed`).

If the worklist has zero PRs: <promise>COMPLETE</promise>

Otherwise, after handling one PR, simply end the task **without** outputting `<promise>COMPLETE</promise>`.
