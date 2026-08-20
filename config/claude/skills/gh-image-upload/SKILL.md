---
name: gh-image-upload
description: Uploads images and files to GitHub (private user-attachments storage) via the gh-image CLI extension and embeds them in PR/issue comments. Use when attaching screenshots, diagrams, logs, or other files to a GitHub PR, issue, or comment from the command line, including headless/sandboxed sessions.
---

# gh-image-upload: attach files to GitHub PRs and issues

Upload images and files to GitHub's `user-attachments` storage from the command line using the [`gh-image`](https://github.com/drogers0/gh-image) extension, and embed the resulting markdown references in PR or issue comments. Upload visibility inherits from the target repository, so uploads to a private repo stay private.

## When to use

When screenshots, diagrams, logs, or other files need attaching to a GitHub PR, issue, or comment: "attach this screenshot to the PR", posting before and after comparisons, or embedding evidence in a bug report.

## Tooling availability

`gh image` is embedded in the `gh` CLI provided by the nixfiles environment (both the Claude sandbox and `nix develop ~/projects/nixfiles#gh-image`). Verify with:

```bash
gh image --version
```

On a machine without the nixfiles gh, fall back to `gh extension install drogers0/gh-image`.

## Authentication with a session token

`gh image` authenticates with a GitHub `user_session` browser cookie, NOT the `gh` API token. Resolution order: the `--token` flag, then the `GH_SESSION_TOKEN` env var, then the browser cookie store.

- Headless and sandboxed runs, including Claude sessions, cannot reach the browser cookie store or Keychain, so `GH_SESSION_TOKEN` must be set in the environment. Check first:
  ```bash
  gh image check-token
  ```
  Exit code 0 and a username on stdout means uploads will work.
- If `check-token` fails, from no token or an invalidated session, do NOT retry-loop or try to read browser cookies yourself. Ask the user to run this in a regular terminal outside the sandbox:
  ```bash
  gh image extract-token   # reads the user_session cookie from Brave, prints the token to stdout
  ```
  and export it as `GH_SESSION_TOKEN`, or provide it for the current run. The token lives as long as the GitHub browser session. It expires only if the user signs out of GitHub in Brave or GitHub invalidates the session.
- **Treat the token like a password.** A `user_session` cookie grants full, unscoped account access. Never echo it into logs, commit it, or pass it via `--token` on shared machines, where `ps aux` shows it. Prefer the env var.
- If uploads are not possible, skip the upload gracefully, keep the local files, and tell the user what was skipped and why.

### Preflight for long-running callers

Callers that do substantial work **before** the upload step must run the token check **at the start of their run**, not at upload time. The visual-comparison skill is one: it captures screenshots for an hour and posts them at the end.

```bash
gh image check-token
```

If it fails, ask the user for the token **then**, via `extract-token` as above, while they are still there to answer. A missing token discovered after the long work is done usually means the user has walked away, and the upload silently degrades to "happy to attach if provided". The check is cheap and read-only, so there is no reason to defer it. If the user chooses to proceed without uploads, record that decision up front and note it in the final output.

Token acquisition, validation, and expiry recovery live in this skill. Callers reference this section rather than restating the mechanics.

## Uploading

```bash
gh image <file>... --repo <owner>/<repo>
```

- Each line of stdout is the ready-to-paste markdown reference for the corresponding input file, **in order**: `![name](url)` for images, a bare URL for videos, which GitHub renders as an inline player, and `[name](url)` for other files. Capture them per file.
- **Always pass `--repo` explicitly**, targeting the repository the comment gets posted to. Visibility inherits from the upload target, so screenshots of internal UIs must not go to a different repo than the PR or issue they document.
- Batch uploads are fine. A failed file prints to stderr and exits non-zero, but the other files in the batch still upload.
- Uploads require write access to the target repository.

## Embedding in a comment

1. **Determine the target.** For the current branch's PR, `gh pr view --json number,url`. If no PR exists yet, skip, tell the user, and offer to post once the PR is opened.
2. **Compose the comment body in a temp file.** The common pattern is a side-by-side before and after table with a collapsed detail image:

   ```markdown
   ### /dashboard
   | Before | After |
   |---|---|
   | ![dashboard-before](…) | ![dashboard-after](…) |
   <details><summary>Diff overlay</summary>

   ![dashboard-diff](…)
   </details>
   ```

   Keep comments scannable. Embed only the images that carry information and list the rest as text, collapsed in `<details>` where long.
3. **Post it**:
   ```bash
   gh pr comment <number> --body-file <tempfile>    # or: gh issue comment <number> ...
   ```
4. Report the comment URL back to the user.
