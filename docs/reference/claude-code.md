# Claude Code configuration

`modules/home/claude-code.nix` deploys the contents of `config/claude/` through the
home-manager `programs.claude-code` module. The package comes from `nextPkgsClaude`.

## Deployed files

| Source | Deployed as |
| --- | --- |
| `config/claude/CLAUDE.md` | `programs.claude-code.context`, embedded in `~/.claude/CLAUDE.md` |
| `config/claude/agents/<name>.md` | Agent `<name>` |
| `config/claude/commands/<name>.md` | Command `<name>` |
| `config/claude/skills/<name>/` | Skill `<name>` |

Agents, commands and skills are enumerated by reading the directory at evaluation time, so a
new file is picked up by adding it and rebuilding. Agent and command names drop the `.md`
suffix; skill names are the directory names.

## Agents

`dependabot`, `fix`, `github-issues`, `github-project`, `loop`, `loop2`, `pr-maintenance`,
`pr-review`, `project`, `project-sleep`, `roadmap-sync`, `tech-spec`.

## Skills

`agent-browser`, `ffmpeg`, `frontend-design`, `gh-image-upload`, `pr-comments`,
`pr-description`, `prd`, `resolve`, `unslop`, `visual-comparison`, `zendesk-ticket`.

## Commands and templates

`config/claude/commands/` holds `quarter-summary.md`. `config/claude/templates/` holds
`ESTIMATION.md` and `tech-spec.md`, which the `github-project` and `tech-spec` packages read
through environment variables set by their derivations.

## Settings

| Setting | Value |
| --- | --- |
| `model` | `opus` |
| `skipDangerousModePermissionPrompt` | `true` |
| `attribution.commit`, `attribution.pr` | empty, which suppresses generated attribution |
| `permissions.allow` | the eight `mcp__codegraph__*` tools |

`env` enables OpenTelemetry export to `localhost:4317` over gRPC, including tool details,
user prompts and session ids.

`enabledPlugins` turns on `ralph-loop`, `rust-analyzer-lsp` and `typescript-lsp` from
`claude-plugins-official`, `aws-cdk` and `aws-cost-ops` from `aws-skills`, and
`document-skills` from `anthropic-agent-skills`. `extraKnownMarketplaces` adds
`pbakaus/impeccable`.

## Hooks

Two `PreToolUse` hooks match `Bash`.

| Hook | Behaviour |
| --- | --- |
| Interpreter guard | Fails the call with a message when the command contains `python3`. |
| `rtk hook claude` | Rewrites commands to run under `rtk`, compressing output before it reaches the context. |

The `rtk` hook command must read exactly `rtk hook claude`, and `rtk` must resolve by bare
name, or rtk's self-check warns daily.

The interpreter guard matches the literal anywhere in the command string, including inside
text that only describes it. Writing about the guard from a shell command trips it.

## MCP servers

Injected through the `--mcp-config` flag by the `claude-code` overlay wrapper and by every
flavour built with `mkClaudeFlavor`, not through `programs.claude-code.mcpServers`. That
option writes no config file. It wraps the binary with a variadic `--mcp-config` ahead of
`"$@"`, which swallows positional arguments, so `claude "prompt"` and `claude mcp list` both
fail under it.

`pkgs.codegraph` and `pkgs.rtk` are installed as ordinary packages so both remain callable
from a shell.
