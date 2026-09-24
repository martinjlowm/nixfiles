---
name: image-upload
description: Uploads screenshots, diagrams, logs and other files to whichever storage backend the session's instructions declare, and embeds the resulting links in GitHub PR and issue comments. Use when attaching files to a PR, issue or comment from the command line, including headless and sandboxed sessions.
---

# image-upload: attach files to GitHub PRs and issues

This skill turns local files into links a reviewer can open, then posts them in a PR or issue
comment. It does not decide where the files are stored. The session's instructions name a
backend, and this skill runs that backend's preflight and upload steps.

## When to use

When screenshots, diagrams, logs, or other files need attaching to a GitHub PR, issue, or
comment: "attach this screenshot to the PR", posting before and after comparisons, or
embedding evidence in a bug report.

## Finding the backend

Look in the instructions already in context (the user's `CLAUDE.md`, the project's
`CLAUDE.md`, or the system prompt) for a section headed `Image uploads`. It names one
backend and says how to use it. When more than one such section is in context, the project's
declaration overrides the user's global one.

A declaration either points at a backend documented in this skill's `backends/` directory or
spells out the steps inline. Either way it supplies four things:

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

With no `Image uploads` section in context, do not guess a backend. Skip the upload, keep
the local files, and tell the user that no upload backend is declared.

## Preflight for long-running callers

Callers that do substantial work **before** the upload step must run the backend's preflight
**at the start of their run**, not at upload time. The visual-comparison skill is one: it
captures screenshots for an hour and posts them at the end.

If the preflight fails, follow the backend's recovery step **then**, while the user is still
there to answer. A failure discovered after the long work is done usually means the user has
walked away, and the upload silently degrades to "happy to attach if provided". The preflight
is cheap and read-only, so there is no reason to defer it. If the user chooses to proceed
without uploads, record that decision up front and note it in the final output.

Backend mechanics (credentials, validation, expiry recovery) live in the backend's
declaration. Callers reference this section rather than restating them.

## Uploading

Run the backend's upload step once per file, or in a batch where the backend supports it,
and keep the URL for each file in input order. When the backend prints bare URLs, wrap each
one yourself:

- `![name](url)` for images.
- A bare URL on its own line for videos, which GitHub renders as an inline player.
- `[name](url)` for other files.

Pick the backend's visibility over convenience. A screenshot of an internal UI must not land
somewhere readable by more people than the PR or issue it documents. When the declared
backend is wider than the target, stop and ask the user.

If uploads are not possible, skip them gracefully, keep the local files, and tell the user
what was skipped and why. Do not retry-loop a failing preflight or go looking for credentials
the declaration does not mention.

## Embedding in a comment

1. **Determine the target.** For the current branch's PR, `gh pr view --json number,url`. If
   no PR exists yet, skip, tell the user, and offer to post once the PR is opened.
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

   Keep comments scannable. Embed only the images that carry information and list the rest
   as text, collapsed in `<details>` where long.
3. **Mention nobody.** No `@handle` anywhere in the body, in running prose or in alt text.
   Every `@` must sit inside a code span or be gone; `grep -n "@[A-Za-z0-9]" <tempfile>` before
   posting. A comment is a notification for everyone already on the thread, and a mention
   pages people who are not.
4. **Post it**:
   ```bash
   gh pr comment <number> --body-file <tempfile>    # or: gh issue comment <number> ...
   ```
5. Report the comment URL back to the user.
