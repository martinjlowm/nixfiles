---
name: resolve
description: Start a focused session on a referenced problem, from a new branch to a draft PR. Use for /resolve, or when asked to "resolve", "fix" or "start a session on" an issue, ticket or bug.
---

# Resolve: branch, solve, draft PR

## Inputs

1. **Problem reference**, required: a GitHub issue (`#123`), a URL, a ticket id, an error
   message, or a plain description.
2. **Base branch**, optional, default `origin/master`. Override it only when the user names
   another.

## Steps

1. **Fetch the base.** `git fetch origin`. If the working tree has uncommitted changes, show
   them to the user before switching branches.
2. **Understand the problem.** `gh issue view <ref>` or `gh pr view <ref>` for GitHub
   references; fetch and read a ticket or URL; work from a free-text description and ask
   only if it is too ambiguous to start. Note the issue that tracks it, since the PR cites
   one (`pr-description` files it when none exists).
3. **Check shared ground.** List the open PRs touching the files you expect to change:

   ```bash
   gh pr list --state open --json number,author,headRefName,files
   ```

   When a colleague's PR changes the same files, say so before going further.
4. **Branch** in the current working directory, never on the base itself:

   ```bash
   git switch -c <branch-name> <base>
   ```

   A short kebab-case name from the problem, such as `fix-login-redirect` or
   `issue-123-timeout`.
5. **Solve it.** Investigate, change, and verify with the project's build, tests and lint.
   Keep the diff to this one problem: no drive-by formatting, renames or unrelated fixes.
   Name anything else you notice in your final message instead.
6. **Commit and push.** A commit message that references the problem, then
   `git push -u origin <branch-name>`.
7. **Open the draft PR.** Load `pr-description`, write the title and body file with it, then:

   ```bash
   gh pr create --draft --base <base> --title "<title>" --body-file <body-file>
   ```

   `--fill` would open the PR on the commit message instead. Post the merge-danger comment
   the skill describes, and return the URL, saying the PR is a draft.
