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

## Repair CI on one of your pull requests

Run `fix` from inside the repository, with a PR number or URL.

```bash
fix 123
fix https://github.com/Org/Repo/pull/123
```

`fix` refuses a pull request that neither you nor Dependabot opened.

## Watch a loop already running

```bash
loop --follow my-task
loop --follow my-task --raw
```

Use `--raw` when the formatted view hides something you need. To read the whole history
instead, open `.state/my-task/loop.log`.

## Skip an iteration that has stalled

Press Escape in the `loop` pane. The current Claude process is killed and the next iteration
starts. The killed iteration is not scanned for control tokens, so a `<promise>` it had
already emitted is discarded. `fix` has no Escape handling.

## Stop a loop

Close the WezTerm tab. Reaching the iteration limit does not end `loop`: it waits for Enter
and starts again from iteration 1.

## Clear loop state

```bash
rm -rf .state/my-task
```

The next run recreates the directory and starts a fresh progress log. The loop adds
`.state/<spec>/` to the repository `.gitignore` on first run, and that line stays behind.
