# Agent Instructions

This agent focuses exclusively on getting existing PRs merged. It does NOT create new PRs or implement new issues.

## Workflow

### Phase 1: Build or refresh the worklist

1. Read `./.state/pr-maintenance/progress.txt` for previously handled PRs and learnings
2. Check if `./.state/pr-maintenance/worklist.json` exists and read it
3. Get current user:
   ```
   gh api user --jq '.login'
   ```
4. List all open, non-draft PRs authored by the current user in the current repo:
   ```
   gh pr list --state open --author @me --search "draft:false" --json number,title,headRefName,body,statusCheckRollup,mergeable,reviewDecision,url
   ```
5. **Create or update** `./.state/pr-maintenance/worklist.json` with ALL open PRs:
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
   - `status` is one of: `pending`, `addressed`, `clean`, `closed`
   - When updating: add newly opened PRs, mark merged/closed PRs as `closed`, preserve status of PRs already tracked
   - Do NOT remove PRs from the list — mark them `closed` so the agent knows they were handled
6. For each PR with `status` of `pending` or `addressed`, assess its health:
   - **Review decision:** check `reviewDecision` from the PR list — `CHANGES_REQUESTED` means the PR needs work regardless of anything else
   - **Review comments:** fetch ALL review threads: `gh api repos/{owner}/{repo}/pulls/{number}/reviews` to find reviews with `state: CHANGES_REQUESTED` or comments. Then fetch inline comments: `gh api repos/{owner}/{repo}/pulls/{number}/comments` — these are file-level review comments. Also check conversation comments: `gh pr view <pr> --comments`. Any unresolved comment (including nits) means the PR needs work
   - **CI:** check `statusCheckRollup` — categorize each check as `passed`, `failed`, `cancelled`, or `pending`:
     - `failed` or `cancelled`: PR needs work
     - `pending`: PR is NOT clean — it stays `addressed` (do not mark `clean` while CI is running)
     - All `passed`: CI is good
   - **Merge conflicts:** is `mergeable` set to `CONFLICTING`?
   - **Issue linkage:** does the PR body contain `Closes <issue-url>`? If the branch name contains an issue number, verify the linkage exists
   - **A PR is `clean` ONLY when ALL of the following are true:**
     - `reviewDecision` is `APPROVED` or has no reviews
     - Zero unresolved review comments (inline and conversation)
     - ALL CI checks have `passed` (not pending, not failed, not cancelled)
     - No merge conflicts (`MERGEABLE`)
     - Issue linkage is correct
   - If any condition is not met, the PR stays `pending` or `addressed` — **never** mark it `clean`
7. Build a prioritized pick list from PRs with `status` of `pending` or `addressed` that have actionable issues (skip PRs whose only issue is pending CI — nothing to do):
   - PRs with `CHANGES_REQUESTED` review decision first
   - PRs with failing/cancelled CI or merge conflicts second
   - PRs with unresolved comments third
   - PRs missing issue linkage last

### Phase 2: Pick and fix ONE PR

8. Pick the first PR from the pick list. If the list is empty, go to the Stop Condition
9. Check out the PR's branch: `git fetch origin <branch> && git checkout <branch>`
10. Enter Nix dev shell before any work (generates pre-commit hooks)
11. Address ALL issues on this PR:
    - **Merge conflicts:** rebase on the PR's base branch and resolve conflicts
    - **Failing CI:** investigate root cause (see **Troubleshooting Cancelled Workflows**), fix the code, commit
    - **PR comments:** address **every** unresolved comment — including nits, style suggestions, and minor feedback. Implement or explain disagreement. Nothing gets ignored
      - **Exception — non-actionable comments:** Skip one-statement comments that are purely observational and don't request any change (e.g., "Interesting feature!", "Nice approach", "Cool"). These require no response or action — replying to them is noisy and unhelpful
      - **Tone in comment replies:** When replying to review threads, only comment on actions taken (e.g., "Fixed", "Updated to use X instead"). Do NOT engage in conversational banter, pick up on jokes or humorous remarks, or attempt to be witty. Keep replies strictly factual and action-oriented
      - **Attribution:** Prefix all PR comments with `🤖 Robotto:`
      - **Self-loop prevention:** Skip any comment that starts with `🤖 Robotto:` — these are from the agent itself. Never respond to your own comments
      - **Code changes require tests:** When implementing code changes in response to review feedback, you MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
      - **References must be accurate:** When commenting on code or adding inline documentation, only reference actual implementation details you have verified. Prefer linking to source code (with the correct tagged version, e.g., `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`) over docs.rs or other generated documentation — docs can drift from the real implementation. Never cite a function's behavior based on documentation alone; read the source to confirm
    - **Missing issue linkage:** if the branch references an issue number, edit the PR body to include `Closes <issue-url>` (`gh pr edit <pr> --body ...`)
    - **Review decision:** if changes were requested, re-request review after addressing all feedback
12. Commit fixes: `[fix|chore](<Component>): Address PR feedback`
13. Push (NEVER force push — merge upstream first)
14. Update `worklist.json`: set the PR's status to `addressed`
15. Log the result in `./.state/pr-maintenance/progress.txt`

**1 PR = 1 iteration.** After completing steps 8–15 for one PR, **end the task** so the next iteration can begin.

**NEVER wait or poll for CI.** Check CI status once — if checks are still running, move on or end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

## Troubleshooting Cancelled Workflows

When most/all jobs show as `cancelled`, one job has a non-zero exit code — the rest are a cascade. "Complete" checks are gate jobs (`needs:` aggregators) — never the root cause.

1. **Identify** the failing job:
   ```
   gh run view {run_id} --log | grep 'exit code' | grep -v 'Complete'
   ```
2. **Investigate** why it failed — grep the full logs for that job name and look for the actual error:
   ```
   gh run view {run_id} --log | grep '{job_name}' | cut -f3- | grep -B10 -i 'error\|failed\|exception'
   ```

Fix only the identified failure; cancelled jobs and gates will pass once resolved.

**Never blindly re-trigger CI.** If a workflow was cancelled, there is always a reason. Do not merge master and push just to re-trigger — investigate why it was cancelled first using the steps above.

**Exception — timeouts:** If a job timed out (`timed_out` conclusion), retry with `gh run rerun {run_id} --failed`. Timeouts are transient infrastructure issues, not code failures.

## Progress Format

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

## Stop Condition

Output `<promise>COMPLETE</promise>` when **every** PR in `worklist.json` has a status of `clean`, `closed`, or is `addressed` with **only** pending CI remaining (no actionable issues — no comments, no conflicts, no failures).

If the worklist has zero PRs: <promise>COMPLETE</promise>

Otherwise, after handling one PR, simply end the task **without** outputting `<promise>COMPLETE</promise>`. The outer loop will start the next iteration.

**NEVER mark a PR `clean` prematurely.** If in doubt, leave it as `pending` or `addressed`. A false `clean` causes the loop to terminate early and miss work.
