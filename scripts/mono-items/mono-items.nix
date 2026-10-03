# rustc's monomorphization collector output for a flake's local Rust crates,
# built through the flake's own crate2nix graph so each crate's dump is a store
# path.
# The runner's `attic watch-store` uploads every path a task builds, so a crate
# whose derivation did not change is a cache hit on the next review.
#
# `agent-mono-items` (mono-items.sh) is the only caller:
#
#   nix eval --impure --json --expr '(import ./mono-items.nix { flake = "path:/w"; }).drvPaths'
#   nix build --impure --expr '(import ./mono-items.nix { flake = "path:/w"; roots = [ "app" ]; }).report'
#
# The flake must expose `legacyPackages.<system>.rustBuild.<profile>`, an
# attrset of workspace members, each a buildRustCrate derivation. Only the
# selected members are instrumented. Their dependencies, local or not, stay the
# derivations the flake builds anyway, so they substitute rather than rebuild.
{
  flake,
  # Workspace member names. null selects every member.
  roots ? null,
  # The graph the instrumented crates' dependencies come from. `release` is
  # the one CI and the fleet build anyway, so those dependencies substitute.
  # The instrumented crates themselves compile with the shim's flags below
  # whatever the profile says.
  profile ? "release",
  system ? builtins.currentSystem,
}: let
  source = builtins.getFlake flake;
  pkgs = source.inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;

  # The profile attrset also holds the cross-compilation sets, which are not
  # derivations.
  members =
    lib.filterAttrs (_: drv: lib.isDerivation drv && drv ? crateName)
    source.legacyPackages.${system}.rustBuild.${profile};
  memberByCrate = lib.mapAttrs' (name: drv: lib.nameValuePair drv.crateName name) members;

  # `completeDeps` is buildRustCrate's transitive library closure.
  localDeps = drv: lib.filter (name: name != null) (map (dep: memberByCrate.${dep.crateName} or null) drv.completeDeps);

  presentRoots = lib.filter (name: members ? ${name}) (
    if roots == null
    then lib.attrNames members
    else roots
  );
  selected = lib.unique (presentRoots ++ lib.concatMap (name: localDeps members.${name}) presentRoots);

  # buildRustCrate calls rustc directly rather than through cargo, so RUSTFLAGS
  # never reaches it. The flags go on through this function instead, which
  # shadows `rustc` for the lib and bin compiles in buildPhase. Build scripts
  # compile in configurePhase, before preBuild defines it, and stay
  # uninstrumented.
  #
  # The collector prints MONO_ITEM lines to stdout and nothing else does, so
  # they are split off into one file per compilation unit. A unit is the crate
  # name plus its crate types, which keeps a package's lib and bin apart.
  #
  # rustc prints a unit's own items without their crate name, so the
  # comparison qualifies them itself. The `--extern` names are what tell it a
  # path's first segment is another crate rather than a local module.
  #
  # Nothing links against an instrumented crate, so its machine code is
  # thrown away. The collector runs before LLVM, so the later flags win over
  # the profile's and skip the optimisation that dominates the build's time
  # and memory: a release `web-api` lib was OOM-killed at 16 GiB.
  # share-generics defaults on at opt-level 0, and `no` keeps the release
  # behaviour that compiles a generic again in each crate needing it. The item
  # set still differs from a real release build where inlining depends on
  # opt-level, identically on both sides of a comparison.
  shim = ''
    rustc() {
      local args=("$@") name="" kinds="" externs=() i
      for ((i = 0; i < ''${#args[@]}; i++)); do
        case "''${args[i]}" in
          --crate-name) name=''${args[i + 1]} ;;
          --crate-type) kinds=''${kinds:+$kinds,}''${args[i + 1]} ;;
          --extern) externs+=("''${args[i + 1]%%=*}") ;;
        esac
      done
      local unit="$name.''${kinds:-lib}"
      mkdir -p "$NIX_BUILD_TOP/mono-items" "$NIX_BUILD_TOP/mono-externs" "$NIX_BUILD_TOP/mono-stats/$unit"
      printf '%s\n' "''${externs[@]}" >"$NIX_BUILD_TOP/mono-externs/$unit"
      RUSTC_BOOTSTRAP=1 command rustc "$@" \
        -Copt-level=0 -Zshare-generics=no -Cdebuginfo=0 \
        -Zprint-mono-items=yes \
        -Zdump-mono-stats="$NIX_BUILD_TOP/mono-stats/$unit" \
        -Zdump-mono-stats-format=json |
        awk -v out="$NIX_BUILD_TOP/mono-items/$unit" '/^MONO_ITEM /{ print > out; next } { print }'
      return "''${PIPESTATUS[0]}"
    }
  '';

  collect = ''
    dest=$out/share/mono-items
    mkdir -p "$dest" "$NIX_BUILD_TOP/mono-items" "$NIX_BUILD_TOP/mono-stats"
    for dir in "$NIX_BUILD_TOP"/mono-stats/*/; do
      [ -d "$dir" ] || continue
      unit=$(basename "$dir")
      touch "$NIX_BUILD_TOP/mono-items/$unit"
      cp "$NIX_BUILD_TOP/mono-items/$unit" "$dest/$unit.items"
      cp "$NIX_BUILD_TOP/mono-externs/$unit" "$dest/$unit.externs"
      stats=$(find "$dir" -name '*.mono_items.json' | head -n 1)
      if [ -n "$stats" ]; then cp "$stats" "$dest/$unit.stats.json"; else echo '[]' >"$dest/$unit.stats.json"; fi
    done
  '';

  # overrideAttrs rather than buildRustCrate's own `.override`: buildRustCrate
  # merges a crate's attributes over its hook arguments, so a crate override
  # that sets preBuild would discard an `.override`.
  instrument = drv:
    drv.overrideAttrs (old: {
      preBuild = shim + (old.preBuild or "");
      postInstall = (old.postInstall or "") + collect;
    });
in {
  inherit selected;

  # Comparing these between two revisions names the members a change reaches:
  # a drvPath covers the crate's source, features and every dependency.
  drvPaths = lib.mapAttrs (_: drv: drv.drvPath) members;

  # One directory per selected member, holding `<unit>.items`,
  # `<unit>.externs` and `<unit>.stats.json` for each of its compilation units.
  report = pkgs.runCommand "mono-items-${profile}" {} ''
    mkdir -p $out
    ${lib.concatMapStringsSep "\n" (name: "ln -s ${instrument members.${name}}/share/mono-items $out/${name}") selected}
  '';
}
