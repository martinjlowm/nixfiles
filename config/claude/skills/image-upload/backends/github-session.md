# github-session backend

Uploads to GitHub's `user-attachments` storage with the
[`gh-image`](https://github.com/drogers0/gh-image) extension. Visibility inherits from the
repository the upload targets, so uploads to a private repo stay private.

## Tooling

`gh image` is embedded in the `gh` CLI that nixfiles provides, both in the Claude sandbox and
in `nix develop ~/projects/nixfiles#gh-image`. Verify with `gh image --version`. If the
machine lacks the nixfiles `gh`, run `gh extension install drogers0/gh-image`.

## Preflight

```bash
gh image check-token
```

Exit code 0 and a username on stdout means uploads will work.

`gh image` authenticates with a GitHub `user_session` browser cookie, not the `gh` API token.
It resolves the cookie from the `--token` flag, then the `GH_SESSION_TOKEN` environment
variable, then the browser cookie store. Headless and sandboxed sessions cannot reach the
cookie store or Keychain, so they need `GH_SESSION_TOKEN`.

## Recovery

If `check-token` fails from a missing token or an invalidated session, ask the user to run
this in a regular terminal outside the sandbox:

```bash
gh image extract-token   # reads the user_session cookie from Brave, prints the token to stdout
```

Ask the user to export the output as `GH_SESSION_TOKEN` or provide it for the current run.
The token lives until the user signs out of GitHub in Brave or GitHub invalidates the session.

Treat the token like a password. A `user_session` cookie grants full, unscoped account
access. Never echo it into logs or commit it. On a shared machine, `ps aux` shows a
`--token` value, so pass it through the environment variable.

## Upload

```bash
gh image <file>... --repo <owner>/<repo>
```

- Each stdout line is the ready-to-paste markdown for the matching input file, in order:
  `![name](url)` for images, a bare URL for videos, and `[name](url)` for other files. No
  wrapping is needed.
- Always pass `--repo`, naming the repository the comment is posted to. Visibility follows
  the upload target, so a screenshot of an internal UI must go to the repo of the PR or issue
  it documents.
- A failed file prints to stderr and exits non-zero. The other files in the batch still
  upload.
- Uploads need write access to the target repository.
