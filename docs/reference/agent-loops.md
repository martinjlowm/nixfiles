# Agent loops

`loop` and `loop2` run a Claude Code session repeatedly against one spec file until the agent
reports completion or the iteration budget runs out. Several packages listed in
[packages](packages.md) are the same machinery with a fixed spec.

## Invocation

```
loop <spec> [max-iterations]
loop --follow <spec> [--raw]
loop --run <spec> [max-iterations]
```

| Form | Effect |
| --- | --- |
| `loop <spec>` | Spawns a WezTerm tab through `mux-spawn` running `--run` beside a `--follow` pane. |
| `loop --follow <spec>` | Tails the Claude session JSONL across iterations through `claude-follow`. `--raw` passes through unformatted. |
| `loop --run <spec>` | Runs the loop in the current terminal. Used internally by the spawned tab. |

`max-iterations` defaults to 10. The spec name resolves to `specs/<spec>.md` under the
repository root, and the loop exits with an error if that file is absent.

## Paths

Resolved against `git rev-parse --show-toplevel`.

| Path | Contents |
| --- | --- |
| `specs/<spec>.md` | The spec. Required. |
| `.state/<spec>/progress.txt` | Progress log. Created with a header on first run. |
| `.state/<spec>/loop.log` | Full output of every iteration. Truncated at loop start. |
| `.state/<spec>/current_session` | Path to the JSONL of the running session. |
| `.state/<spec>/next-instructions.md` | Pending handoff. `loop2` only. |
| `.state/<spec>/next-instructions.last.md` | Most recently consumed handoff. `loop2` only. |
| `~/.claude/agents/loop.md`, `loop2.md` | Prompt template. `__SPEC__` is replaced with the spec name. |
| `~/.claude/agents/project-sleep.md` | Appended to every prompt. |

On first run the loop appends `.state/<spec>/` to the repository `.gitignore` if no line
already mentions it.

## Control tokens

The loop greps each iteration's output for these.

| Token | Effect |
| --- | --- |
| `<promise>COMPLETE</promise>` | Reports done, waits for Enter, then restarts the loop from iteration 1. |
| `<promise>SLEEP</promise>` | Calls `claude-sleep` with the current sleep count and continues without consuming an iteration. |
| `<next>...</next>` | `loop2` only. Persists the wrapped text as the next iteration's handoff. |

Any other output ends the iteration normally and resets the sleep count to zero.

## Handoff, loop2 only

When an iteration emits a `<next>` block, `loop2` writes the contents to
`next-instructions.md`. The following iteration copies that file to
`next-instructions.last.md`, deletes it, and builds its prompt as the handoff text under a
precedence header followed by the standard workflow. A handoff therefore applies to exactly
one iteration.

The prompt states that the handoff overrides the standard workflow, and that the workflow
applies only where the handoff is silent.

## Interactive control

Pressing Escape during an iteration kills the Claude process and starts the next iteration.
An escaped iteration is not scanned for control tokens.

At the iteration limit the loop reports the limit, waits for Enter and restarts.

## Environment

Before each iteration the loop creates `$CARGO_TARGET_DIR`, or `target/` when that variable
is unset. safehouse resolves its bind mounts with `realpath` and fails on a missing path.
