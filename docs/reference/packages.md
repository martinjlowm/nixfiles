# Packages

Every runnable package this flake defines, where it is defined, and how it is exposed.

Script sources live in `scripts/*.sh` and are wrapped by `scripts/default.nix`. Most are
built with `mkWeztermScript`, which wraps the shell source in `pkgs.writeShellApplication`
with `wezterm`, `mux-spawn`, `claude-follow` and `claude-sleep` on `PATH`. The wrapper
supplies the interpreter and the executable bit, so the `.sh` sources carry no shebang and
are mode 644.

## Exposed as flake packages

Runnable as `nix run github:martinjlowm/nixfiles#<name> -- [args]`. Declared by the
`scriptNames` list in `flake.nix`.

| Package | Arguments | Description |
| --- | --- | --- |
| `claude-code` | passthrough | Claude Code under a sandbox. safehouse on macOS, bubblewrap on Linux. |
| `dependabot` | none | Agent loop that processes open Dependabot pull requests. |
| `fix` | `<pr-number>` | Agent loop that repairs CI on one pull request. |
| `github-issues` | none | Agent loop over GitHub Issues. |
| `github-project` | `<tech-spec.md> <project-url>` | Creates project items from a tech spec. Reads `ESTIMATION_TEMPLATE`, set by the derivation. |
| `gh-image` | passthrough | `gh` extension that uploads images to GitHub user-attachments storage. |
| `gh-with-image` | passthrough | `gh` with the `gh-image` extension already installed. |
| `loop` | `<spec> [max-iterations]` | Generic spec-driven agent loop. Default 10 iterations. |
| `playwright-at` | `<chrome-major-version>` | Playwright pinned to a given Chrome major version. |
| `pr-maintenance` | none | Agent loop over pull request health and review feedback. |
| `pr-review` | none | Agent loop that reviews pull requests. |
| `project` | none | Agent loop over a GitHub Project board. |
| `rmtree` | `<path>` | Interactive recursive delete. Derived from llimllib's `rmtree`, unlicense. |
| `tech-spec` | `<notion-url> [output-file]` | Fills a tech spec template from a Notion product spec. Reads `TECH_SPEC_TEMPLATE` and `TECH_SPEC_MCP_CONFIG`. |
| `worktree` | `[-v] [-b <ref>] <branch>` | Creates a git worktree for `<branch>`, branching from `origin/master` or `origin/main` unless `-b` names another ref. Copies `.env`, `.envrc` and `.tool-versions` across, using copy-on-write where the filesystem supports it. |

Six repository-analytics scripts are also exposed. Each reads the git history of the current
repository and takes no arguments.

| Package | Reports |
| --- | --- |
| `git-bug-hotspots` | Files appearing most often in bug-fix commits. |
| `git-commit-velocity` | Monthly commit counts across the whole history. |
| `git-contributor-rankings` | All-time contributor ranking by commit count. |
| `git-firefighting` | Reverts, hotfixes and emergency commits. |
| `git-most-changed` | The 20 highest-churn files of the past year. |
| `git-recent-contributors` | Contributor ranking over a recent window. |

## Installed on the Darwin host only

Listed in `modules/darwin/packages.nix` and absent from `flake.nix`, so they arrive with a
`darwin-rebuild switch` and are not reachable through `nix run`.

| Package | Arguments | Description |
| --- | --- | --- |
| `claude-dbg` | passthrough | Claude Code with the SignOZ MCP server. Reads a SigNoz API token from 1Password at startup and fails if it is absent. |
| `claude-ops` | passthrough | Claude Code with the Sentry and Datadog MCP servers. |
| `claude-pm` | passthrough | Claude Code with the Notion, Figma and Drata MCP servers. |
| `pr-pr` | none | Lists own open non-draft pull requests that have reviewers but no approval, grouped by assignee, suggesting further reviewers from recent authorship of the changed files. |
| `pr-ready` | none | Lists own open non-draft pull requests that are approved and free of merge conflicts. |
| `pr-ua` | none | Lists own open non-draft pull requests that are unapproved, not marked changes-requested, and whose reviewers need prompting. |
| `roadmap-sync` | none | Interactive roadmap sync session. |
| `zendesk-ticket` | passthrough | Reads Zendesk tickets and their attachments. |

The three `claude-*` flavours are built by `mkClaudeFlavor`, which writes an MCP config
combining `pkgs.codegraph-mcp-servers` with the flavour's own servers. An explicitly declared
server wins a name clash against codegraph. Each flavour generates a session id with
`uuidgen` unless the invocation carries `--resume` or `--continue`.

## Defined but not installed

Present in `scripts/default.nix` and referenced from no package set.

| Package | Description |
| --- | --- |
| `codegraph-pull` | Downloads the published codegraph index for the current repository when a newer one exists. |
| `loop2` | `loop` plus the handoff baton. See [agent loops](agent-loops.md). |

## Build helpers

Not user-facing. `scripts/default.nix` defines them for the packages above to depend on:
`chrome-devtools-mcp`, `claude-follow`, `claude-sleep`, `mkClaudeFlavor`, `mkWeztermScript`,
`mux-spawn`, `signoz-mcp-server`, `wezterm`.
