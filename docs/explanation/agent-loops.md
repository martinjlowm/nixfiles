# Why the agent loops are shaped this way

A Claude Code session ends. That is the whole problem these loops exist to solve. The work
they are pointed at, clearing a Dependabot queue, repairing CI, grinding through a project
board, does not fit in one session and does not fail in ways a single session can recover
from. So the loop restarts the session and lets the filesystem carry what the context cannot.

## Why a spec file rather than a prompt

The prompt is generated per iteration from a template with the spec name substituted in, and
the spec itself lives in the repository as `specs/<name>.md`. Keeping the task in a file
rather than in a shell argument means the task can be edited while the loop runs. The next
iteration reads the current file. In practice that is how these loops get steered: you watch
a few iterations go wrong, you fix the spec, and the correction lands without stopping
anything.

It also means the loop is a general tool with a thin skin over it. `dependabot`, `fix` and
`pr-review` are the same machinery with a fixed spec, which is why they cost a few lines each
in `scripts/default.nix`.

## Why state lives on disk

Progress, the session id, and the log all live under `.state/<spec>/`. None of it is
information the agent could hold anyway, since each iteration is a fresh session, and putting
it in files makes it inspectable from another terminal while the loop runs. The follower pane
exists for exactly that.

The directory is gitignored, and the loop appends the ignore line itself on first run. That
is a small piece of self-installation which avoids the alternative of a stale ignore list
that has to be maintained by hand for every spec anyone invents.

## Why control tokens rather than exit codes

An iteration signals completion by printing `<promise>COMPLETE</promise>` and asks to back off
by printing `<promise>SLEEP</promise>`. The loop greps stdout for these.

Exit codes would be cleaner if the agent controlled the process, but it does not: `claude`
exits zero whether the work is done or the model gave up. A token the model must deliberately
emit is a stronger signal than an exit status it does not own. The cost is that a token
mentioned in passing would be read as the real thing, which is a real weakness of the design
and the reason the tokens are shaped like markup nobody types by accident.

Sleep is separate from completion because the two failures look identical from outside. A loop
hammering a rate limit and a loop with nothing to do both produce fast, empty iterations.
`SLEEP` lets the agent say which one is happening, and `claude-sleep` backs off further each
consecutive time.

## Why loop2 is a separate script rather than a flag

`loop2` adds one thing: an iteration can leave a `<next>` block, and the following iteration
gets that text at the top of its prompt with explicit precedence over the standard workflow.
It is a baton, consumed once, archived beside the live file.

This could have been a flag on `loop`. Keeping it separate is a deliberate trade. `loop`
builds one prompt and reuses it for every iteration, and every existing spec relies on that.
Threading per-iteration precedence through the same script would change the prompt for specs
that never asked for it, and the failure mode would be silent: a spec would start behaving
differently with no edit to explain why.

The duplication is real. `loop2` is `loop` plus 44 lines and the two will drift. That is the
price of not touching a working script that other specs depend on, and it is worth paying
until the handoff is proven enough to fold back in.

## What the handoff is actually for

The obvious reading is that it lets an agent leave itself a note. The useful reading is that
it lets an iteration change what the next iteration is for. An agent that discovers halfway
through a queue that the queue is the wrong shape can hand forward a new instruction rather
than fighting the spec for the remaining iterations.

That is also why the handoff outranks the standard workflow in the prompt rather than being
appended to it. A note that the workflow can override is a note that gets ignored.
