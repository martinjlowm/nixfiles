---
name: resolve
description: Start a focused session on a referenced problem, from a new branch to a draft PR. Use for /resolve, or when asked to "resolve", "fix" or "start a session on" an issue, ticket or bug.
---

# Resolve: branch, solve, draft PR

## Inputs

1. **Problem reference**, required: a GitHub issue (`#123`), a URL, a ticket id, an error
   message, or a plain description.
2. **Base branch**, optional, default `origin/master`. Use another only if the user names it.

## Steps

1. **Fetch the base.** `git fetch origin`. If the working tree has uncommitted changes, show
   them to the user before switching branches.
2. **Understand the problem.** For a GitHub reference, run `gh issue view <ref>` or
   `gh pr view <ref>`. Fetch and read a ticket or URL. Work from a free-text description,
   and ask only if it is too ambiguous to start. Note the issue that tracks the problem,
   because the PR cites one. If none exists, `pr-description` files it.
3. **Check shared ground.** List the open PRs touching the files you expect to change:

   ```bash
   gh pr list --state open --json number,author,headRefName,files
   ```

   If a colleague's PR changes the same files, say so before going further.
4. **Branch** in the current working directory, never on the base itself:

   ```bash
   git switch -c <branch-name> <base>
   ```

   Name the branch in short kebab-case after the problem, such as `fix-login-redirect` or
   `issue-123-timeout`.
5. **Solve it.** Investigate, change, and verify with the project's build, tests and lint.
   Keep the diff to this one problem, with no drive-by formatting or renames.
6. **Commit and push.** Reference the problem in the commit message, then run
   `git push -u origin <branch-name>`.
7. **Open the draft PR.** Load `pr-description`, write the title and body file with it, then:

   ```bash
   gh pr create --draft --base <base> --title "<title>" --body-file <body-file>
   ```

   Do not pass `--fill`, which opens the PR on the commit message. Post the merge-danger
   comment the skill describes, and return the URL.
