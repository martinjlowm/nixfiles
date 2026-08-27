# nixfiles

My Nix battle station: a nix-darwin and home-manager configuration for one MacBook, plus the
agent tooling that runs on it.

Two things live here. The first is an ordinary system configuration, with hosts, modules,
overlays and a `flake.nix`. The second is a set of shell packages that drive Claude Code
against a repository, either interactively or in a loop that restarts the session until the
work is done.

## Documentation

- **[Tutorial](docs/tutorial.md)** sets up a new Mac from nothing. Start here if you have not
  used this configuration before.
- **How-to guides** answer a specific question.
  - [Run a package without installing anything](docs/how-to/run-a-package-without-installing.md)
  - [Run an agent loop](docs/how-to/run-an-agent-loop.md)
  - [Add a script package](docs/how-to/add-a-script-package.md)
  - [Extend the Claude Code configuration](docs/how-to/extend-claude-code.md)
  - [Update dependencies and rebuild](docs/how-to/update-and-rebuild.md)
- **Reference** describes what is here.
  - [Packages](docs/reference/packages.md)
  - [Repository layout](docs/reference/repository-layout.md)
  - [Agent loops](docs/reference/agent-loops.md)
  - [Claude Code configuration](docs/reference/claude-code.md)
- **Explanation** covers why it is built this way.
  - [Why the agent loops are shaped this way](docs/explanation/agent-loops.md)
  - [Why Claude Code runs in a sandbox](docs/explanation/sandboxing.md)
  - [Why there are four nixpkgs inputs](docs/explanation/nixpkgs-pinning.md)

## Run something now

On a machine with Nix:

```bash
nix run github:martinjlowm/nixfiles#claude-code
```

On a machine without it, `bootstrap.sh` installs Determinate Nix first:

```bash
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh \
  | bash -s -- fix 123
```

## What is in here

**Sandboxed Claude Code.** `claude-code` wraps the upstream binary in safehouse on macOS and
bubblewrap on Linux, with the codegraph MCP server attached. Three further flavours add
integrations for their own work: `claude-pm` for Notion, Figma and Drata, `claude-ops` for
Sentry and Datadog, `claude-dbg` for SignOZ.

**Agent loops.** `loop` runs a Claude session against a spec file over and over, tracking
progress on disk and reading control tokens out of each iteration's output. `loop2` adds a
handoff: an iteration can leave instructions that outrank the standard workflow for the next
one. `dependabot`, `fix`, `github-issues`, `pr-maintenance`, `pr-review` and `project` are the
same machinery with a fixed spec.

**Pull request tools.** `pr-ua`, `pr-pr` and `pr-ready` sort your open pull requests by what
they are waiting on: reviewers who need prompting, reviewers who need suggesting, and branches
clear to merge.

**Repository analytics.** Six git history reports covering churn, bug hotspots, commit
velocity, firefighting, and contributor rankings all-time and recent.

**Claude Code configuration.** `config/claude/` holds the global instructions, twelve agents,
eleven skills, and the commands and templates the `tech-spec` and `github-project` packages
read. It is deployed by home-manager and enumerated from the directory, so adding a file and
rebuilding is enough.

**Everything else.** `worktree` creates git worktrees with copy-on-write for ignored
directories, `rmtree` deletes interactively, `gh-image` uploads images to GitHub from the
command line, `tech-spec` fills a spec template from Notion, and `github-project` turns that
spec into project items.

The complete list, including which packages are reachable through `nix run` and which arrive
only with a rebuild, is in [packages](docs/reference/packages.md).
