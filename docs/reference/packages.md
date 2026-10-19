# Packages

Every runnable package this flake defines, where it is defined, and how it is exposed.

Script sources live in `scripts/*.sh` and are wrapped by `scripts/default.nix` in
`pkgs.writeShellApplication`, which supplies the interpreter and the executable bit, so the
`.sh` sources carry no shebang and are mode 644. `loop` and `fix` are built with
`mkWeztermScript`, which puts `wezterm`, `mux-spawn`, `claude-follow` and `claude-sleep` on
`PATH` and exports the store paths of the package's prompt, `ci-triage.md`,
`loop-sleep.md` and `loop-disclosure.md` from `config/claude/loops/`.

## Exposed as flake packages

Runnable as `nix run github:martinjlowm/nixfiles#<name> -- [args]`. Declared by the
`scriptNames` list in `flake.nix`.

| Package | Arguments | Description |
| --- | --- | --- |
| `claude-code` | passthrough | Claude Code under a sandbox. safehouse on macOS, bubblewrap on Linux. |
| `fix` | `<pr-number-or-url> [max-iterations]` | Agent loop that repairs CI on one pull request. Refuses a pull request whose author is neither the `gh` user nor `app/dependabot`. |
| `gh-axi` | passthrough | Agent-facing wrapper over `gh` with TOON output. Built from the npm tarball against `lockfiles/gh-axi.json`. |
| `gh-image` | passthrough | `gh` extension that uploads images to GitHub user-attachments storage. |
| `gh-with-image` | passthrough | `gh` with the `gh-image` extension already installed. |
| `loop` | `<spec> [max-iterations]` | Generic spec-driven agent loop. Default 10 iterations. |
| `playwright-at` | `<chrome-major-version>` | Playwright pinned to a given Chrome major version. |
| `rmtree` | `<path>` | Interactive recursive delete. Derived from llimllib's `rmtree`, unlicense. |
| `tech-spec` | `<notion-url> [output-file]` | Fills a tech spec template from a Notion product spec. Reads `TECH_SPEC_PROMPT`, `TECH_SPEC_TEMPLATE` and `TECH_SPEC_MCP_CONFIG`. |
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
| `pr-attn` | `[--all] [--no-drafts]` | Lists own open pull requests waiting on the author, meaning an unresolved review thread whose last comment came from a human other than you, or a pull request whose newest comment, review or thread reply came from one. Every account GitHub types as a `Bot` is skipped on both counts. Covers the repository the working directory resolves to, and fails where no GitHub remote resolves; `--all` spans every repository and prefixes each line with the one it belongs to. Reads the first 100 review threads and the last 20 comments and reviews per pull request. |
| `pr-pr` | none | Lists own open non-draft pull requests that have reviewers but no approval, grouped by assignee, suggesting further reviewers from recent authorship of the changed files. |
| `pr-ready` | none | Lists own open non-draft pull requests that are approved and free of merge conflicts. |
| `prq` | `[--all] [--drafts] [--audit] [--plain]` | Lists own open pull requests in fzf by who holds the ball: `you` (a reviewer spoke after your last comment or push, a peer's comment is unanswered, or an unresolved thread ends with a peer), `re-request` (a reviewer commented or requested changes, you answered since, and no request is pending), `unassigned`, `waiting` and `approved`. Draws stacks as trees by following base branches to other listed pull requests, with approved layers over total. Shows each `priority: <level>` label as the level's first letter, every reviewer's standing with request age, new peer comments, threads on you, CI and conflicts, and the cached comment-audit and scope-audit result for the head. Every account GitHub types as a `Bot` is skipped. Covers the repository of the working directory; `--all` spans every repository. `--audit` runs the two scorers for each head not audited yet, which needs `TYPESAFE_API_KEY` and a checkout of the repository as the working directory, and caches results under `$XDG_CACHE_HOME/prq`. In fzf, `enter` opens the pull request, `ctrl-r` re-requests the reviewers marked `↻`, `ctrl-a` audits the selection, `ctrl-b` starts an agent session on the agents console from a brief of what is open on the pull request and `ctrl-l` refetches. The session posts to the console's `POST /new` with the head branch as its ref, authenticated by the `__Host-mj_session` cookie in `MJ_AGENTS_SESSION`, and gives up after 30 seconds. Without that variable, or when the console refuses it or does not answer, the brief goes to the clipboard and the console's new-session form opens with the repository, ref and brief in its `/new?repository=&ref=&prompt=` query, which the console renders as the form's initial values. `PRQ_AGENTS_URL` overrides the console URL. Reads the last 50 reviews, 30 comments, and 100 review threads of 10 comments each per pull request. |
| `rebuild` | `[<action>] [flags]` | Runs `darwin-rebuild <action> --flake <flake>#$(hostname -s) -L`, where `<action>` defaults to `switch` and `<flake>` is the first directory at or above `$PWD` holding both `flake.nix` and `hosts/`, falling back to `projects/nixfiles` under the home of `$SUDO_USER`. The action `home` instead builds `<flake>#homeConfigurations.$USER.activationPackage` with the flags passed to `nix build` and runs its `activate`, and exits with an error when run as root. Prepends `/run/current-system/sw/bin` to `PATH`. |
| `roadmap-sync` | none | Interactive roadmap sync session in `~/projects/pm` through `claude-pm`. Reads `ROADMAP_SYNC_PROMPT`. |
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

## Build helpers

Not user-facing. `scripts/default.nix` defines them for the packages above to depend on:
`chrome-devtools-mcp`, `claude-follow`, `claude-sleep`, `mkClaudeFlavor`, `mkWeztermScript`,
`mux-spawn`, `signoz-mcp-server`, `wezterm`.
