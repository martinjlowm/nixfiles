# Why there are four nixpkgs inputs

`flake.nix` takes `nixpkgs` from the `nixos-26.05` release branch and then three more inputs,
`nextNixpkgs`, `nextNixpkgsDevenv` and `nextNixpkgsClaude`, each pinned to a bare commit.

The release branch is the base because a system configuration wants a package set that
changes on a schedule someone else is testing. The three pins exist because a handful of
packages move faster than that, and waiting six months for a Claude Code release is not
sensible when the tool changes weekly.

## Why pinned revisions rather than a branch

Each `next` input names a commit, not `nixos-unstable`. Tracking unstable would mean every
`nix flake update` moves the whole package set underneath one package that needed updating.
Pinning to a revision makes the update deliberate: you bump the hash in `flake.nix` when you
want the newer thing, and `nix flake update` leaves it alone.

The cost is that these pins go stale silently. Nothing warns you that `nextNixpkgsClaude` is
four months behind. That is a real weakness of the arrangement, traded for not having a system
rebuild change a dozen packages you were not thinking about.

## Why they reach modules through specialArgs

`mkDarwinSystem` builds a package set per input and passes `nextPkgs`, `nextPkgsDevenv` and
`nextPkgsClaude` to modules through `specialArgs`, alongside the same values in
`home-manager.extraSpecialArgs`. A module takes the argument it needs:

```nix
{nextPkgsClaude, ...}: {
  programs.claude-code.package = nextPkgsClaude.claude-code;
}
```

The alternative, an overlay that replaces `claude-code` in the base set, would make the newer
version invisible at the call site. Anything depending on it would silently pick up a package
from a different nixpkgs with no hint in the module. Naming the set at the point of use keeps
the exception legible, at the price of another module argument.

`mkNixosSystem` passes only `nextPkgs`, because the Linux side does not currently need the
other two.
