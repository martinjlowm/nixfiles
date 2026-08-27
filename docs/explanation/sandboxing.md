# Why Claude Code runs in a sandbox

The `claude-code` package here is not the upstream binary. The overlay wraps it in safehouse
on macOS and bubblewrap on Linux, and the wrapper passes
`--dangerously-skip-permissions` inside that sandbox.

Those two facts are the same decision. Permission prompts and a sandbox are two answers to
the same question, and running both means answering it twice. The prompts stop being a
security control the moment you are answering dozens an hour, because you stop reading them.
What survives the fatigue is a boundary the agent cannot talk its way past. So the boundary is
the filesystem, and inside it the agent does not ask.

The trade is stated plainly: an agent inside the sandbox can do anything to the directories
the sandbox exposes. The protection is the size of the box, not the agent's restraint.

## Why the policy is generated per command

The sandbox profile is built at invocation rather than baked once. The directories a session
needs depend on what it is doing, and a profile wide enough for every command would be wide
enough to be pointless.

This is also why the loops create `$CARGO_TARGET_DIR` before each iteration. safehouse
resolves its bind mounts with `realpath` and fails on a path that does not exist yet. A fresh
checkout, or a `cargo clean`, would otherwise break the next iteration with an error that
points at the sandbox rather than at the missing directory.

## Why MCP config is passed as a flag

Every flavour and the wrapper itself inject MCP servers with `--mcp-config`.
`programs.claude-code.mcpServers` from home-manager looks like the declarative option and is
the wrong tool: it writes no file, and instead wraps the binary with a variadic flag placed
ahead of `"$@"`. A variadic flag in front of positional arguments eats them, so `claude
"prompt"` and `claude mcp list` both fail under it.

Discovering that cost an afternoon, which is why the reason is written in the module next to
the code rather than left for the next person to rediscover.

## Why codegraph is in every flavour

`mkClaudeFlavor` merges codegraph into whatever servers a flavour declares, and an explicit
server of the same name wins. Codegraph is a pre-built index of the workspace, so it makes the
difference between an agent that greps its way around a repository and one that looks a symbol
up. That is worth having in every flavour by default, and the override exists so a flavour
that needs a different index is not blocked by the default.
