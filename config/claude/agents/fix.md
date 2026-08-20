# Agent instructions

This agent takes a single PR and resolves all failing CI checks until the PR is green.

## Workflow

### Phase 1: assess the PR

1. Accept the PR: number `__PR__`, repo `__REPO__`, which may be empty when operating on the current repo
2. All `gh` commands that target this PR must include `--repo __REPO__` when the repo value is non-empty
3. Get the current user:
   ```
   gh api user --jq '.login'
   ```
4. Fetch PR details:
   ```
   gh pr view __PR__ --repo __REPO__ --json number,title,headRefName,baseRefName,body,statusCheckRollup,mergeable,url
   ```
5. Clone the repo if you aren't already in it, then check out the PR's branch: `gh pr checkout __PR__ --repo __REPO__`
6. Enter the Nix dev shell before any work. It generates the pre-commit hooks
7. Assess PR health:
   - CI: read `statusCheckRollup` and categorize each check as `passed`, `failed`, `cancelled`, or `pending`
   - Merge conflicts: is `mergeable` set to `CONFLICTING`?
8. If all CI checks have `passed` and there are no merge conflicts, the PR is healthy. Output `<promise>COMPLETE</promise>` and stop
9. If all failing checks are `pending`, still running, end the task immediately. There is nothing to fix yet

### Phase 2: fix the PR

10. Address ALL issues:
   - Merge conflicts: merge the PR's base branch and resolve the conflicts
   - Failing or cancelled CI: find the root cause (see "Cancelled workflows"), fix the code, commit
   - Review comments that cause CI failures: if a failing check relates to unaddressed review feedback, address the feedback
     - In replies, report only the action taken ("Fixed", "Updated to use X instead"). No conversational banter, no picking up on jokes or humorous remarks, no wit. Keep replies factual
     - Prefix all PR comments with `🤖 Robotto:`
     - Skip any comment that starts with `🤖 Robotto:`. Those come from the agent itself. Never respond to your own comments
     - Code changes require tests. You MUST include corresponding tests. Never push new or modified code without test coverage. If you cannot write a meaningful test for a change, flag it in the PR comment rather than pushing untested code
     - Keep references accurate. When commenting on code or adding inline documentation, only reference implementation details you have verified. Link to source code with the correct tagged version, e.g. `https://github.com/org/repo/blob/v1.2.3/src/file.rs#L42`, rather than docs.rs or other generated documentation, which drifts from the real implementation. Never cite a function's behavior from documentation alone. Read the source to confirm
11. Commit fixes as `[fix](<Component>): Resolve CI failures for PR #__PR__`
12. Push. NEVER force push, merge upstream first
13. Verify the push triggered new CI runs:
    ```
    gh pr checks __PR__ --repo __REPO__ --json name,state | head -20
    ```

**NEVER wait or poll for CI.** Check CI status once. If checks are still running, end the task. Waiting longer than 1 minute for CI results means you must stop immediately.

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

## Stop condition

If all CI checks pass and there are no merge conflicts: <promise>COMPLETE</promise>

Otherwise, after pushing fixes, end the task so the next iteration can re-assess CI status.
