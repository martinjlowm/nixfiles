# Add a script package

## Write the script

Put the source at `scripts/<name>.sh`. Write no shebang and leave the file mode at 644.
`writeShellApplication` supplies the interpreter and the executable bit, and a shebang here
is dead text.

Resolve repository paths through `git rev-parse --show-toplevel` rather than `$0`, because
the script runs from the Nix store.

## Wrap it

Add an attribute to `scripts/default.nix`. For a script that spawns a WezTerm tab and uses
the loop helpers:

```nix
<name> = mkWeztermScript "<name>";
```

`mkWeztermScript` reads `./<name>.sh`, so the file must exist and be tracked by git before
the flake can evaluate it. Anything else needs its own `writeShellApplication`:

```nix
<name> = pkgs.writeShellApplication {
  name = "<name>";
  runtimeInputs = [pkgs.jq pkgs.gh];
  checkPhase = "";
  text = builtins.readFile ./<name>.sh;
};
```

Set `checkPhase = ""` to skip the shellcheck run, matching the surrounding entries.

## Expose it

Adding the attribute does not install the package. Pick where it should appear.

| Goal | Edit |
| --- | --- |
| Reachable by `nix run` on any machine | Add the name to `scriptNames` in `flake.nix` |
| Installed on the Mac | Add `scripts.<name>` to `modules/darwin/packages.nix` |
| Both | Do both. Most packages are in both lists. |

A package in neither list is defined and unreachable.

## Commit the source with the wiring

`builtins.readFile` resolves against the flake source, and a flake copies only tracked files.
An untracked `scripts/<name>.sh` evaluates on the machine where it sits in the working tree
and fails everywhere else.

```bash
git add scripts/<name>.sh scripts/default.nix flake.nix
```

## Build it

```bash
nix build .#<name>
./result/bin/<name>
```

Then `darwin-rebuild switch --flake .#wololobook` to install it.
