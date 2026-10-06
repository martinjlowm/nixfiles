# Claude Code configuration

`modules/home/claude-code.nix` deploys the contents of `config/claude/` through the
home-manager `programs.claude-code` module. The package comes from `nextPkgsClaude`.

## Deployed files

| Source | Deployed as |
| --- | --- |
| `config/claude/CLAUDE.md`, then `config/claude/rules/github.md` and `rules/writing.md` | `programs.claude-code.context`, concatenated in that order into `~/.claude/CLAUDE.md` |
| `config/claude/agents/<name>.md` | Subagent `<name>` |
| `config/claude/commands/<name>.md` | Command `<name>` |
| `config/claude/skills/<name>/` | Skill `<name>` |

Agents, commands and skills are enumerated by reading the directory at evaluation time, so a
new file is picked up by adding it and rebuilding. Agent and command names drop the `.md`
suffix; skill names are the directory names. Rules files are not enumerated. The
`sharedRules` list in `modules/home/claude-code.nix` names them. `config/claude/loops/` and
`config/claude/templates/` are not deployed to `~/.claude`; the packages that use them read
them from the Nix store.

## Rules

`config/claude/rules/` holds the rules shared by laptop and fleet sessions.

| File | Covers |
| --- | --- |
| `github.md` | Mentions, draft PRs, `pr-description`, one change per PR, review requests and the merge queue, shared ground, review threads, posting once |
| `writing.md` | `unslop` and its six binding items, claiming only checked work, code comments, aligned diagrams, the four documentation modes |

The mj-agents fleet builds its house rules from the same two files, read from its
`claude-config` flake input.

## Agents

Every file in `config/claude/agents/` is a subagent with YAML frontmatter.

| Agent | Role |
| --- | --- |
| `incident-root-cause` | Investigates one incident signal for the incident RCA routine |
| `pentest-surface-probe` | Probes one staging surface for the weekly pentest routine |
| `pr-review-orchestrator` | Runs the PR-review pipeline over the agents below |
| `review-cdk-infra` | Reviews AWS CDK changes |
| `review-claim-verifier` | Verifies one review claim against dependency source and docs |
| `review-code-comments` | Reviews the code comments a PR adds or leaves |
| `review-patterns-types-errors` | Reviews patterns, types, error handling and naming |
| `review-perf-claim-verifier` | Verifies one review claim that rests on a measurement |
| `review-rust-mono-items` | Compares monomorphization output between a Rust PR and its base |
| `review-tests-perf-security` | Reviews conventions, coupling, tests, performance and security |
| `review-visual` | Runs `visual-comparison` for a PR that changes UI |

mj-agents bakes these into its image by name, from its `nixfilesAgentNames` list.

## Loop prompts

`config/claude/loops/` holds the prompts the loop packages send to `claude`. Each
derivation in `scripts/default.nix` exports the store path of its prompt in an environment
variable.

| File | Read by | Variable |
| --- | --- | --- |
| `loop.md` | `loop` | `LOOP_PROMPT` |
| `fix.md` | `fix` | `LOOP_PROMPT` |
| `ci-triage.md` | `loop`, `fix` | `LOOP_CI_TRIAGE_PROMPT` |
| `loop-sleep.md` | `loop`, `fix` | `LOOP_SLEEP_PROMPT` |
| `roadmap-sync.md` | `roadmap-sync`, as an appended system prompt | `ROADMAP_SYNC_PROMPT` |
| `tech-spec.md` | `tech-spec` | `TECH_SPEC_PROMPT` |

## Skills

`agent-browser`, `ffmpeg`, `frontend-design`, `gh-axi`, `image-upload`, `pr-comments`,
`pr-description`, `prd`, `resolve`, `review-protocol`, `unslop`, `visual-comparison`,
`zendesk-ticket`.

`review-protocol` sets `user-invocable: false`. It holds the protocol the `review-*` agents
and claim verifiers read before their own instructions: constraints, evidence, comment
craft, the finding schema and the result file.

Three flake inputs supply skills from outside `config/claude/skills/`. All are
`flake = false`.

| Skill | Input | Path in the input |
| --- | --- | --- |
| `fleet-conversation` | `agent-skills` (FactbirdHQ/agent-skills) | `fleet-conversation` |
| `show-me` | `humanlayer-skills` (humanlayer/skills) | `plugins/show-me/skills/show-me` |
| `retro` | `mattpocock-skills` (mattpocock/skills) | `skills/engineering/retro` |
| `writing-for-agents` | `mattpocock-skills` (mattpocock/skills) | `skills/productivity/writing-for-agents` |

`show-me` and `retro` set `disable-model-invocation`, so only the user can invoke them as
skills. `retro` loads `writing-for-agents` as its first step.
The diagram rule in `rules/writing.md` and `pr-description` read its `SKILL.md` from
`~/.claude/skills/show-me/` for the views a diagram or a PR body draws.

`image-upload` stores files with the backend named in an `Image uploads` section of the
instructions in context. `config/claude/CLAUDE.md` declares `github-session`, documented in
`config/claude/skills/image-upload/backends/github-session.md`. A project declaration
overrides it.

## Commands and templates

`config/claude/commands/` holds `quarter-summary.md`. `config/claude/templates/` holds
`tech-spec.md`, which the `tech-spec` package reads through `TECH_SPEC_TEMPLATE`, and
`ESTIMATION.md`, which no package or prompt reads.

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

The TypeSafe agent skill (`typesafe-ai/skills`) is not one of these: it is fetched in the
`claude-code` overlay and passed to every session with a trailing `--plugin-dir`, the same way
codegraph is passed `--mcp-config`, because `programs.claude-code.plugins` has the same
positional-argument-swallowing wrapper bug already worked around for `mcpServers`. `TYPESAFE_API_KEY`
is resolved from 1Password (`op://Developer/Jev/credential`) alongside `GH_TOKEN`.

## Sandbox PATH

The `claude-code` overlay wrapper prepends two directories to `PATH`.

| Directory | Provides |
| --- | --- |
| `ghWrapped` | `gh`, built from `gh-with-image`, with `--admin` removed from every invocation. `GH_CONFIG_DIR` points at an empty store path, so auth comes from `GH_TOKEN`. |
| `pkgs.gh-axi` | `gh-axi`, which runs `gh` by bare name and therefore goes through `ghWrapped`. |

`gh-axi setup hooks` is not run. The `SessionStart` hook it would install prints `0 open`
issues and pull requests outside a GitHub repository, rather than an explicit empty state.

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
