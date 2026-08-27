# Run a package without installing anything

Use this on a machine you do not own, a fresh VM, or a CI runner.

## If Nix is already available

```bash
nix run github:martinjlowm/nixfiles#<package> -- [args...]
```

## If Nix may be missing

`bootstrap.sh` installs Determinate Nix when it cannot find an existing installation, then
runs the package.

```bash
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh \
  | bash -s -- <package> [args...]
```

It looks for `nix` on `PATH` first, then sources each of the three common profile scripts
before deciding to install. If the install succeeds but `nix` still does not resolve, it
tells you to open a new shell and gives you the `nix run` line to use there.

Only the packages in the flake's `packages` output are reachable this way. The Darwin-only
packages are not; see [packages](../reference/packages.md).

## Pin to a revision

Append a revision to the flake reference when you need the same result twice.

```bash
nix run github:martinjlowm/nixfiles/<rev>#<package>
```
