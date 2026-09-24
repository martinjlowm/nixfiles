---
name: gh-axi
description: Operate GitHub through the gh-axi CLI. Use whenever a task reads or changes GitHub state from the shell - viewing or listing issues and PRs, checking CI runs and failed job logs, reading PR reviews and diffs, commenting, creating draft PRs, workflows, releases, labels, Projects, or REST API calls. Prefer it over raw `gh` except where this skill says otherwise.
user-invocable: false
---

# gh-axi

`gh-axi` is on PATH in every sandboxed session. It runs the sandbox's `gh`, so it shares that
binary's auth and flag filtering, and prints compact TOON with totals and `help:` lines that
name the next command to run.

## Discover commands from the CLI

```bash
gh-axi                      # dashboard for the current repo
gh-axi --help               # command index and global flags
gh-axi <command> --help     # flags and examples for one command
```

Follow the `help:` lines in each output instead of guessing flags. Unknown flags fail with a
`VALIDATION_ERROR` that lists the supported ones.

## Common calls

```bash
gh-axi pr view 42 --reviews          # PR state, checks bucketed pass/fail/skip/pending, reviews
gh-axi pr view 42 --comments
gh-axi pr checks 42
gh-axi pr diff 42
gh-axi run view <run-id> --log-failed   # tail of failed job logs; full log saved to a temp file
gh-axi pr create --draft --title "..." --body-file body.md
gh-axi pr comment 42 --body-file reply.md
gh-axi search issues "flaky test" --repo owner/name
```

Long bodies, diffs and logs are truncated with a size hint. Pass `--full` when the elided part
matters.

## When to use `gh` instead

- `gh api graphql`, and any `gh api` call that needs `-f`/`-F`. `gh-axi api` accepts only
  `--field`, `--header`, `--input`, `--paginate`, `--jq`, `--template` and `--full`.
- Output piped into `jq` or another program. TOON is for reading, not for parsing.
- `gh image`, which the `image-upload` skill's `github-session` backend documents.
- A script or skill that already spells out a `gh` pipeline. Run it as written.

## Rules that still apply

The global instructions on GitHub bind `gh-axi` exactly as they bind `gh`. PRs are created
with `--draft`, and `gh-axi pr ready` is never run. Bodies are grepped for `@` mentions
before they are posted.
