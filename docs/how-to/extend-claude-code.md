# Extend the Claude Code configuration

Agents, commands and skills under `config/claude/` are enumerated at evaluation time, so
adding a file is enough. Rebuild afterwards with `darwin-rebuild switch --flake .#wololobook`.

## Add a skill

```bash
mkdir -p config/claude/skills/<name>
$EDITOR config/claude/skills/<name>/SKILL.md
```

Give it YAML frontmatter with `name` and `description`. The description decides when the
skill gets invoked, so write it as the trigger conditions rather than a summary. The
directory name becomes the skill name.

## Add a subagent or a command

```bash
$EDITOR config/claude/agents/<name>.md
$EDITOR config/claude/commands/<name>.md
```

The filename without `.md` becomes the name. A subagent needs YAML frontmatter with `name`
and `description`. A prompt that a script pipes into `claude` is not a subagent and goes in
`config/claude/loops/` instead.

## Add a loop prompt

Put the prompt in `config/claude/loops/<name>.md` and have the package's derivation in
`scripts/default.nix` export its store path, as `mkWeztermScript` does with `LOOP_PROMPT`.
Read the variable in the script rather than a path under `~/.claude`.

## Change global instructions

A rule that holds for fleet sessions as well goes in `config/claude/rules/github.md` or
`rules/writing.md`, since mj-agents builds its house rules from the same files. A new rules
file also needs its name added to `sharedRules` in `modules/home/claude-code.nix`, and to the
fleet's list if the fleet should read it.

A laptop-only instruction goes in `config/claude/CLAUDE.md`. Leave the `rtk-instructions`
comment markers alone: they delimit a generated block.

Both are concatenated into `~/.claude/CLAUDE.md` through `programs.claude-code.context`.

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
