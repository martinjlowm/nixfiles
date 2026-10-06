# Why the agent loops are shaped this way

A Claude Code session ends. That is the whole problem these loops exist to solve. The work
they are pointed at, working through a spec story by story or repairing CI, does not fit in
one session and does not fail in ways a single session can recover from. So the loop restarts the session and lets the filesystem carry what the context cannot.

## Why a spec file rather than a prompt

The prompt is generated per iteration from a template with the spec name substituted in, and
the spec itself lives in the repository as `specs/<name>.md`. Keeping the task in a file
rather than in a shell argument means the task can be edited while the loop runs. The next
iteration reads the current file. In practice that is how these loops get steered: you watch
a few iterations go wrong, you fix the spec, and the correction lands without stopping
anything.

It also means the loop is a general tool with a thin skin over it. `fix` is the same
machinery with a fixed prompt, which is why it costs one line in `scripts/default.nix`.

## Why the prompts are not in `~/.claude`

The prompts once lived in `config/claude/agents/`, which home-manager deploys as subagents.
They have no frontmatter and are not subagents, so every consumer of that directory had to
know which files to skip, and the mj-agents fleet keeps an explicit list for that reason.
Moving them to `config/claude/loops/` and handing each script a store path keeps the agents
directory to real subagents, and ties the prompt a loop runs to the build of its script.

## Why most of the loops were retired

The loop family once included `dependabot`, `pr-maintenance`, `pr-review`, `github-issues`,
`project`, `github-project` and `loop2`. The mj-agents fleet now runs the first four jobs
from GitHub events, with scope checks and an identity of its own, and `project` overlapped
the fleet's issue delivery. The laptop versions acted as the user on shared repositories:
they approved and queued PRs, replied to every thread and posted status updates under the
user's name. `github-project` overlapped the `prd` skill. `loop2` duplicated `loop`
line for line to add a handoff between iterations, and no package set installed it.

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
