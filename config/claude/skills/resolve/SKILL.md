---
name: resolve
description: Start a focused session to solve a referenced problem. Creates a new branch off a base (origin/master by default) and opens a PR, then works in the current working directory to resolve the problem. Use when the user invokes /resolve, or asks to "resolve", "fix", or "start a session on" a referenced problem, issue, ticket, or bug.
---

# Resolve — branch, PR, and solve a referenced problem

Create a PR and a new branch off of `origin/master` and use the current working directory to solve the referenced problem. Use `origin/master` as the base branch unless the user specifies otherwise.

## When to use

When the user invokes `/resolve <problem reference>` — where the reference is an issue, ticket, PR, error, or free-text description of a problem to solve. The intent is to reference a problem and start a session dedicated to solving it.

## Inputs from the user

1. **Problem reference** (required) — what to solve. Can be a GitHub issue (`#123`), a URL, a ticket ID, an error message, or a plain-language description.
2. **Base branch** (optional) — defaults to `origin/master`. Only override when the user explicitly names a different base.

## Steps

1. **Fetch the latest base.** Run `git fetch origin` so the new branch starts from the up-to-date tip of the base branch.

2. **Understand the problem.** Resolve the reference into concrete context:
   - GitHub issue / PR number or URL → `gh issue view <ref>` / `gh pr view <ref>`.
   - A ticket or external URL → fetch and read it.
   - Free-text description → work from what the user gave you; ask a clarifying question only if the problem is too ambiguous to start.

3. **Create the branch.** Branch off the base (default `origin/master`, or the user-specified base) in the current working directory:

   ```bash
   git switch -c <branch-name> origin/master
   ```

   Pick a short, descriptive kebab-case branch name derived from the problem (e.g. `fix-login-redirect`, `issue-123-timeout`). Do not work directly on the base branch.

4. **Solve the problem.** Work in the current working directory to implement the fix. Investigate, make the changes, and verify them (build/tests/lint as appropriate for the project).

5. **Commit and push.** Commit the change with a clear message that references the problem, then push and set the upstream:

   ```bash
   git push -u origin <branch-name>
   ```

6. **Open the PR.** Create a pull request against the base branch:

   ```bash
   gh pr create --base master --fill
   ```

   Write a title and body that reference the original problem (link the issue with `Closes #123` when applicable) and summarize the change. Return the PR URL to the user.

## Notes

- Always branch off the base — never commit directly to `origin/master`.
- If the working directory has uncommitted changes, surface them before switching branches so nothing is lost.
- Keep the session focused on the referenced problem; if you discover unrelated issues, note them rather than expanding scope.
