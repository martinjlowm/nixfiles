# Set up a new Mac

By the end of this you will have Nix installed, this configuration built on your machine, and
one of its commands running in your shell. It takes about half an hour, most of it waiting for
builds.

You need a Mac with Apple Silicon, an internet connection, and an administrator password.

## 1. Install Nix

Paste this into Terminal:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

The installer asks for your password and prints a summary of what it will do. Answer yes. It
finishes in a minute or two.

Now close Terminal completely and open it again. The installer edits your shell profile, and
only a new shell picks that up.

Check that it worked:

```bash
nix --version
```

You should see a version number. If you see "command not found", close and reopen Terminal
once more.

## 2. Get the configuration

```bash
mkdir -p ~/projects
git clone https://github.com/martinjlowm/nixfiles ~/projects/nixfiles
cd ~/projects/nixfiles
```

Everything below happens in this directory.

## 3. Build one command

Before building a whole system, build a single package. This proves the flake evaluates on
your machine and warms the cache.

```bash
nix build .#git-most-changed
```

The first run downloads a lot and takes several minutes. It prints nothing when it succeeds
and leaves a symlink called `result` behind.

Run what you just built:

```bash
./result/bin/git-most-changed
```

It prints the twenty files in this repository that changed most in the past year. You have
now run code from this configuration.

## 4. Build the system configuration

```bash
nix run nix-darwin -- switch --flake .#wololobook
```

`wololobook` is the name of the machine this configuration was written for. You are building
that machine's configuration on yours, which is what you want for a first run.

This is the long step. It installs the applications, the shell setup, and every script in
`scripts/`. Let it finish.

When it completes, close Terminal and open it again.

## 5. Use it

```bash
git-most-changed
```

The same command as in step 3, now on your `PATH` without a `result` symlink. Try one more:

```bash
git-contributor-rankings
```

That ranks everyone who has committed to this repository.

## 6. Make a change and apply it

Open `config/claude/CLAUDE.md` and add a line at the bottom:

```markdown
# Scratch

Hello from my first rebuild.
```

Apply it:

```bash
darwin-rebuild switch --flake .#wololobook -L
```

`darwin-rebuild` is on your `PATH` now, so you no longer need `nix run nix-darwin`. The `-L`
shows you the build log as it goes.

Confirm the change landed:

```bash
grep -A2 "^# Scratch" ~/.claude/CLAUDE.md
```

Your edit is in the generated file. Remove the lines you added and rebuild once more to put
the file back:

```bash
darwin-rebuild switch --flake .#wololobook -L
```

## What you have

Nix, this configuration built and activated, and the loop from edit to rebuild to result. You
ran a package before building anything large, built the system, and changed a file that the
build reads.

To adapt the configuration to your own machine rather than borrowing `wololobook`, start from
[repository layout](reference/repository-layout.md) and copy `hosts/darwin/wololobook/`.
