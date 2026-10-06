# Agent loops

`loop` runs a Claude Code session repeatedly against one spec file until the agent reports
completion or the iteration budget runs out. `fix` is the same machinery with a fixed prompt
that targets one pull request. Both are listed in [packages](packages.md).

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

## Prompt

Each iteration pipes one prompt into `claude`, built from three files in
`config/claude/loops/`, read from the Nix store through variables the derivation exports.

| File | Variable | Part |
| --- | --- | --- |
| `loop.md` | `LOOP_PROMPT` | The workflow. `__SPEC__` is replaced with the spec name. |
| `ci-triage.md` | `LOOP_CI_TRIAGE_PROMPT` | Appended. How to find the failing job in a CI run. |
| `loop-sleep.md` | `LOOP_SLEEP_PROMPT` | Appended. When to emit `SLEEP`. |

## Paths

Resolved against `git rev-parse --show-toplevel`.

| Path | Contents |
| --- | --- |
| `specs/<spec>.md` | The spec. Required. |
| `.state/<spec>/prd.json` | Stories and their `passes` state. Read and written by the agent. |
| `.state/<spec>/progress.txt` | Progress log. Created with a header on first run. |
| `.state/<spec>/loop.log` | Full output of every iteration. Truncated at loop start. |
| `.state/<spec>/current_session` | Path to the JSONL of the running session. |

On first run the loop appends `.state/<spec>/` to the repository `.gitignore` if no line
already mentions it.

## Control tokens

The loop greps each iteration's output for these.

| Token | Effect |
| --- | --- |
| `<promise>COMPLETE</promise>` | Reports done, waits for Enter, then restarts the loop from iteration 1. |
| `<promise>SLEEP</promise>` | Calls `claude-sleep` with the current sleep count and continues without consuming an iteration. |

Any other output ends the iteration normally and resets the sleep count to zero.

## Interactive control

Pressing Escape during an iteration kills the Claude process and starts the next iteration.
An escaped iteration is not scanned for control tokens.

At the iteration limit the loop reports the limit, waits for Enter and restarts.

## Environment

Before each iteration the loop creates `$CARGO_TARGET_DIR`, or `target/` when that variable
is unset. safehouse resolves its bind mounts with `realpath` and fails on a missing path.
