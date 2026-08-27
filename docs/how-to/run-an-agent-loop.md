# Run an agent loop

## Run a loop against your own spec

Write the spec, then start the loop.

```bash
mkdir -p specs
$EDITOR specs/my-task.md
loop my-task
```

`loop` opens a WezTerm tab with the loop on one side and a session follower on the other. It
stops after 10 iterations unless you raise the budget.

```bash
loop my-task 30
```

If the spec file does not exist, the loop prints the path it expected and exits.

## Run one of the fixed-spec loops

`dependabot`, `fix`, `github-issues`, `pr-maintenance`, `pr-review` and `project` carry their
own spec. Run them from inside the repository you want them to work on.

```bash
fix 123          # repair CI on PR 123
dependabot       # process open Dependabot PRs
```

## Watch a loop already running

```bash
loop --follow my-task
loop --follow my-task --raw
```

Use `--raw` when the formatted view hides something you need. To read the whole history
instead, open `.state/my-task/loop.log`.

## Skip an iteration that has stalled

Press Escape in the loop pane. The current Claude process is killed and the next iteration
starts. The killed iteration is not scanned for control tokens, so a `<promise>` or `<next>`
block it had already emitted is discarded.

## Hand instructions to the next iteration

Only `loop2` reads handoffs, and it is not currently installed by any package set. Run it
from the source tree.

```bash
./scripts/loop2.sh my-task
```

Have the agent end an iteration with a `<next>` block. The text inside is injected at the top
of the following iteration's prompt, above the standard workflow, and applies to that one
iteration only. The consumed text is kept at `.state/my-task/next-instructions.last.md`.

## Stop a loop

Close the WezTerm tab. Reaching the iteration limit does not end the loop: it waits for Enter
and starts again from iteration 1.

## Clear loop state

```bash
rm -rf .state/my-task
```

The next run recreates the directory and starts a fresh progress log. The loop adds
`.state/<spec>/` to the repository `.gitignore` on first run, and that line stays behind.
