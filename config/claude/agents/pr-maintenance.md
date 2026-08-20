# Agent instructions

This agent does one thing: get existing PRs merged. It does NOT create new PRs or implement new issues.

## Workflow

### Phase 0: repository setup

Detect the repo layout and set up accordingly:

```
git rev-parse --is-bare-repository
```

**Bare repository (`true`):** use a shared `maintenance` worktree. Always use the `worktree` command in PATH. That is NOT `git worktree` and NOT the `EnterWorktree` tool.

1. Check whether a `maintenance` worktree already exists:
   ```
   git worktree list --porcelain | grep -A2 'worktree.*maintenance$'
   ```
2. If it does **not** exist, create one:
   ```
   worktree maintenance --base origin/master
   ```
3. If it **does** exist, reuse it. `cd` into the worktree path and update it:
   ```
   cd <worktree-path>
   git fetch origin master
   git merge origin/master
   ```
4. All subsequent work happens **inside the worktree**. State files (`.state/pr-maintenance/`) live in the **main repo**, not the worktree. Use absolute paths or `$REPO_ROOT/.state/pr-maintenance/` when reading and writing state.

**Regular repository (`false`):** work directly in the checkout. No worktree setup is needed. PR branches get checked out directly in Phase 2.

### Phase 1: build or refresh the worklist

1. Read `./.state/pr-maintenance/progress.txt` for previously handled PRs and learnings
2. Check whether `./.state/pr-maintenance/worklist.json` exists and read it
3. Get the current user:
   ```
   gh api user --jq '.login'
   ```
4. List all open, non-draft PRs authored by the current user in the current repo:
   ```
   gh pr list --state open --author @me --search "draft:false" --json number,title,headRefName,body,statusCheckRollup,mergeable,reviewDecision,url
   ```
5. Create or update `./.state/pr-maintenance/worklist.json` with ALL open PRs:
   ```json
   {
     "created_at": "<ISO>",
     "updated_at": "<ISO>",
     "prs": [
       {
         "number": 123,
         "title": "PR title",
         "branch": "feat/my-branch",
         "url": "https://github.com/owner/repo/pull/123",
         "status": "pending"
       }
     ]
   }
   ```
   - `status` is one of `pending`, `addressed`, `clean`, `closed`
   - When updating, add newly opened PRs, mark merged and closed PRs as `closed`, and preserve the status of PRs already tracked
   - Do NOT remove PRs from the list. Mark them `closed` so the agent knows they were handled
6. For each PR with `status` of `pending` or `addressed`, assess its health:
   - Review decision: check `reviewDecision` from the PR list. `CHANGES_REQUESTED` means the PR needs work regardless of anything else
   - Review comments: fetch ALL review threads with `gh api repos/{owner}/{repo}/pulls/{number}/reviews` to find reviews with `state: CHANGES_REQUESTED` or comments. Then fetch inline, file-level comments with `gh api repos/{owner}/{repo}/pulls/{number}/comments`. Also check conversation comments with `gh pr view <pr> --comments`. Only consider comments authored by `{current_user}`, the `@me` login from step 3, or by `claude[bot]`, that are NOT prefixed with `🤖 Robotto:`. Ignore comments from all other users. Any unresolved comment from `@me` or `claude[bot]`, including nits, means the PR needs work
   - CI: read `statusCheckRollup` and categorize each check as `passed`, `failed`, `cancelled`, or `pending`:
     - `failed` or `cancelled`: the PR needs work
     - `pending`: the PR is NOT clean. It stays `addressed`. Do not mark `clean` while CI is running
     - All `passed`: CI is good
   - Merge conflicts: is `mergeable` set to `CONFLICTING`?
   - Issue linkage: does the PR body contain `Closes <issue-url>`? If the branch name contains an issue number, verify the linkage exists
   - **A PR is `clean` ONLY when ALL of the following are true:**
     - `reviewDecision` is `APPROVED` or the PR has no reviews
     - Zero unresolved review comments, inline and conversation
     - ALL CI checks have `passed`, not pending, not failed, not cancelled
     - No merge conflicts (`MERGEABLE`)
     - Issue linkage is correct
   - If any condition fails, the PR stays `pending` or `addressed`. **Never** mark it `clean`
7. Build a prioritized pick list from PRs with `status` of `pending` or `addressed` that have actionable problems. Skip PRs whose only problem is pending CI, since there is nothing to do:
   - PRs with a `CHANGES_REQUESTED` review decision first
   - PRs with failing or cancelled CI, or merge conflicts, second
   - PRs with unresolved comments third
   - PRs missing issue linkage last

### Phase 2: pick and fix ONE PR

8. Pick the first PR from the pick list. If the list is empty, go to the stop condition
9. Check out the PR's branch:
   - Bare repo, inside the `maintenance` worktree: `git fetch origin <branch> && git checkout <branch>`
   - Regular repo: `git fetch origin <branch> && git checkout <branch>`
10. Enter the Nix dev shell before any work. It generates the pre-commit hooks
11. Address ALL problems on this PR:
    - Merge conflicts: merge the PR's base branch and resolve the conflicts
    - Failing CI: find the root cause (see "Cancelled workflows"), fix the code, commit
    - PR comments: address **every** unresolved comment, including nits, style suggestions, and minor feedback. Implement it or explain the disagreement. Nothing gets ignored
      - Non-actionable comments are the exception. Skip one-statement comments that are purely observational and request no change ("Interesting feature!", "Nice approach", "Cool"). They need no response or action, and replying is noise
      - In replies to review threads, report only the action taken ("Fixed", "Updated to use X instead"). No conversational banter, no picking up on jokes or humorous remarks, no wit. Keep replies factual
      - Prefix all PR comments with `🤖 Robotto:`
      - Skip any comment that starts with `🤖 Robotto:`. Those come from the agent itself. Never respond to your own comments
      - Code changes require tests. When implementing changes in response to review feedback, you MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
      - Keep references accurate. When commenting on code or adding inline documentation, only reference implementation details you have verified. Link to source code with the correct tagged version, e.g. `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`, rather than docs.rs or other generated documentation, which drifts from the real implementation. Never cite a function's behavior from documentation alone. Read the source to confirm
    - Missing issue linkage: if the branch references an issue number, edit the PR body to include `Closes <issue-url>` (`gh pr edit <pr> --body ...`)
    - Review decision: do NOT re-request reviews. Instead, update the PR description to summarize what changed since the last review so reviewers can see at a glance what was addressed
12. Commit fixes as `[fix|chore](<Component>): Address PR feedback`
13. Update the PR description (`gh pr edit <pr> --body ...`) to reflect the changes you made. Append a "Changes since last review" section summarizing what was addressed
14. Push. NEVER force push, merge upstream first
15. Update `worklist.json`: set the PR's status to `addressed`
16. Log the result in `./.state/pr-maintenance/progress.txt`

**1 PR = 1 iteration.** After completing steps 8 through 16 for one PR, **end the task** so the next iteration can begin.

**NEVER wait or poll for CI.** Check CI status once. If checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Cancelled workflows

When most or all jobs show as `cancelled`, one job exited non-zero and the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators), never the root cause.

1. Identify the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. Find out why it failed. Grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```

Fix only the identified failure. Cancelled jobs and gates pass once it is resolved.

**Never blindly re-trigger CI.** A cancelled workflow always has a reason. Do not merge master and push just to re-trigger. Investigate first using the steps above.

Timeouts are the exception. If a job timed out (`timed_out` conclusion), retry with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure problems, not code failures.

## Progress format

Append to `./.state/pr-maintenance/progress.txt`:
```
## [Date] - PR #[number]
- Title: [PR title]
- What was addressed: [comments, CI, conflicts, linkage]
- Files changed
- Learnings: patterns, gotchas
---
```

**progress.txt is strictly for implementation notes and learnings.** Do NOT write:
- CI status, check results, or pass/fail state
- Batch status listings across multiple PRs
- "Next iteration" action items or plans

## Stop condition

Output `<promise>COMPLETE</promise>` when **every** PR in `worklist.json` has a status of `clean` or `closed`, or is `addressed` with **only** pending CI remaining, meaning no comments, no conflicts, and no failures.

If the worklist has zero PRs: <promise>COMPLETE</promise>

Otherwise, after handling one PR, end the task **without** outputting `<promise>COMPLETE</promise>`. The outer loop starts the next iteration.

**NEVER mark a PR `clean` prematurely.** If in doubt, leave it as `pending` or `addressed`. A false `clean` ends the loop early and misses work.
