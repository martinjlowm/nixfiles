# Update dependencies and rebuild

## Rebuild after a local change

```bash
sudo rebuild
```

`rebuild` builds `darwinConfigurations.$(hostname -s)` from the repository the working
directory sits in, with full build logs. Activation runs as root, so it needs `sudo`. The
host is also reachable as `Martins-MacBook-Pro`, an alias for the same configuration.

Run it from outside the repository and it falls back to `~/projects/nixfiles`.

## Check a change before switching

```bash
rebuild build
```

This builds without activating. To see what a switch would change, compare the result
against the running system:

```bash
nix store diff-closures /run/current-system ./result
```

## Update every input

```bash
nix flake update
sudo rebuild
```

## Update one input

```bash
nix flake update nixpkgs
```

The three `nextNixpkgs*` inputs are pinned to explicit revisions rather than a branch, so
`nix flake update` will not move them. Bump the revision in `flake.nix` to move one.

## Roll back

```bash
darwin-rebuild switch --rollback
```

Or boot an earlier generation from the list:

```bash
darwin-rebuild --list-generations
```

## Recover from a failed evaluation

If evaluation fails on a missing file that exists in your working tree, it is untracked. A
flake copies only tracked files.

```bash
git status --short
git add <the missing file>
```
