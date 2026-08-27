# Extend the Claude Code configuration

Everything under `config/claude/` is enumerated at evaluation time, so adding a file is
enough. Rebuild afterwards with `darwin-rebuild switch --flake .#wololobook`.

## Add a skill

```bash
mkdir -p config/claude/skills/<name>
$EDITOR config/claude/skills/<name>/SKILL.md
```

Give it YAML frontmatter with `name` and `description`. The description decides when the
skill gets invoked, so write it as the trigger conditions rather than a summary. The
directory name becomes the skill name.

## Add an agent or a command

```bash
$EDITOR config/claude/agents/<name>.md
$EDITOR config/claude/commands/<name>.md
```

The filename without `.md` becomes the name.

## Change global instructions

Edit `config/claude/CLAUDE.md`. It is deployed as `programs.claude-code.context` and embedded
into `~/.claude/CLAUDE.md`. Leave the `rtk-instructions` comment markers alone: they delimit
a generated block.

## Add an MCP server to a flavour

Edit the flavour's `mcpServers` in `scripts/default.nix`.

```nix
claude-ops = mkClaudeFlavor {
  name = "claude-ops";
  purpose = "...";
  mcpServers = {
    sentry = { type = "http"; url = "https://mcp.sentry.dev/sse"; };
  };
};
```

codegraph is merged into every flavour. Declaring a server named `codegraph` overrides it.

If the server needs a credential, fetch it in `preExec` and fail loudly when it is missing.
`claude-dbg` does this for its SigNoz token.

## Add a whole new flavour

```nix
claude-<name> = mkClaudeFlavor {
  name = "claude-<name>";
  purpose = "One line, shown to the user";
  runtimeInputs = [pkgs.jq];
  mcpServers = { ... };
};
```

Then add `scripts.claude-<name>` to `modules/darwin/packages.nix`. The flavours are not in
the flake's `packages` output.

## Do not declare MCP servers through home-manager

`programs.claude-code.mcpServers` writes no config file. It wraps the binary with a variadic
`--mcp-config` ahead of `"$@"`, which swallows positional arguments, so `claude "prompt"` and
`claude mcp list` both break. Pass `--mcp-config` from the wrapper instead, as the overlay
and `mkClaudeFlavor` do.
