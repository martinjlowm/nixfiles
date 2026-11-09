---
name: image-upload
description: Upload screenshots and other files to the backend the session declares and embed them in GitHub PR or issue comments. Use when attaching files to a PR, issue or comment.
---

# image-upload: attach files to GitHub PRs and issues

This skill turns local files into links a reviewer can open and posts them in a PR or issue
comment. The session's instructions name the backend that stores the files. This skill runs
that backend's preflight and upload steps.

## When to use

Use it to attach screenshots, diagrams, logs or other files to a GitHub PR, issue or comment.

## Finding the backend

Look for a section headed `Image uploads` in the user's `CLAUDE.md`, the project's
`CLAUDE.md` or the system prompt. It names one backend and says how to use it. If more than
one such section is in context, the project's declaration overrides the user's global one.

A declaration points at a backend in this skill's `backends/` directory or spells out the
steps inline. Either way it supplies four things:

| Part | What it states |
| --- | --- |
| Preflight | A cheap, read-only command whose success means uploads will work. |
| Upload | How one local file becomes a URL, and what the command prints. |
| Visibility | Who can open the URL, and which targets that makes the backend fit for. |
| Recovery | What to ask the user for when the preflight fails. |

Documented backends:

| Name | File | Storage |
| --- | --- | --- |
| `github-session` | [backends/github-session.md](backends/github-session.md) | GitHub user-attachments, authenticated with a browser session cookie. |
| `session-assets` | [backends/session-assets.md](backends/session-assets.md) | The agent fleet's S3 bucket, served from a public URL. |

If no `Image uploads` section is in context, do not guess a backend. Skip the upload, keep
the local files, and tell the user that no upload backend is declared.

## Preflight for long-running callers

A caller that does substantial work **before** the upload step must run the preflight **at
the start of its run**. The visual-comparison skill is one
such caller.

If the preflight fails, follow the backend's recovery step **then**, while the user is still
there to answer. After the long work, the user has usually walked away. If the user chooses to
proceed without uploads, record that decision up front and note it in the final output.

Credentials, validation and expiry recovery live in the backend's declaration. Callers
reference this section and do not restate them.

## Uploading

Run the backend's upload step once per file, or in a batch if the backend supports it. Keep
the URL for each file in input order. If the backend prints bare URLs, wrap each one yourself:

- `![name](url)` for images.
- A bare URL on its own line for videos, which GitHub renders as an inline player.
- `[name](url)` for other files.

A screenshot of an internal UI must not land somewhere readable by more people than the PR
or issue it documents. If the declared backend is wider than the target, stop and ask the
user, unless the backend's Visibility section already settles it.

If uploads are not possible, skip them, keep the local files, and tell the user what was
skipped and why. Do not retry a failing preflight in a loop. Do not look for credentials the
declaration does not mention.

## Embedding in a comment

1. **Determine the target.** For the current branch's PR, run `gh pr view --json number,url`.
   If no PR exists yet, skip, tell the user, and offer to post once the PR is opened. If an
   earlier run already posted this comment, edit that comment in place with
   `gh pr comment <number> --edit-last` or a PATCH on its id.
2. **Compose the comment body in a temp file.** The common pattern is a side-by-side before
   and after table with a collapsed detail image:

   ```markdown
   ### /dashboard
   | Before | After |
   |---|---|
   | ![dashboard-before](…) | ![dashboard-after](…) |
   <details><summary>Diff overlay</summary>

   ![dashboard-diff](…)
   </details>
   ```

   Embed only the images that carry information. List the rest as text, collapsed in
   `<details>` if long.
3. **Post it**:
   ```bash
   gh pr comment <number> --body-file <tempfile>    # or: gh issue comment <number> ...
   ```
4. Report the comment URL back to the user.
