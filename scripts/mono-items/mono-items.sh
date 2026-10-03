# Compares rustc's mono items between two revisions of a Rust workspace
# flake (see mono-items.nix for the shape it expects), for the
# review-rust-mono-items subagent. Packaged as `agent-mono-items`
# (writeShellApplication: shellcheck, strict mode, pinned PATH) by
# scripts/default.nix and by mj-agents' devenv.nix.
#
#   agent-mono-items <checkout> <base-sha> <head-sha> <out-dir>
#
# Both revisions are checked out as detached worktrees under <out-dir>, so the
# session's own checkout is never touched. Every member's drvPath is evaluated
# on both sides, and the members whose drvPath differs, plus their local
# dependencies, are built instrumented by mono-items.nix. A member whose
# derivation is the same on both sides is the same store path, built once.
#
# <out-dir> receives:
#   affected.json        members whose derivation differs, or that exist only on head
#   base/, head/         the two report store paths, as out-links
#   base.log, head.log   nix's stderr for each build
#   report.md            the comparison, rendered for a review body
#   regressions.json     every newly duplicated item, unabridged
#   status               compared | not_applicable | failed, last line written
#
# Exit codes: 0 compared or not_applicable; 1 a build or the comparison failed,
# with the reason in status and the logs.
#
# MONO_ITEMS_NIX and MONO_ITEMS_DIFF name mono-items.nix and the comparison
# CLI. The package sets both; run standalone they default to this checkout's
# copies.
if [ "$#" -ne 4 ]; then
  echo "usage: agent-mono-items <checkout> <base-sha> <head-sha> <out-dir>" >&2
  exit 2
fi
checkout=$(realpath "$1")
base_sha=$2
head_sha=$3
out=$4
here=$(dirname "$(realpath "$0")")
nix_file=${MONO_ITEMS_NIX:-$here/mono-items.nix}
diff_cli=${MONO_ITEMS_DIFF:-$here/cli.ts}

mkdir -p "$out"
out=$(realpath "$out")
status() {
  echo "$1" >"$out/status"
  echo "agent-mono-items: $1" >&2
}

# `path:` rather than `git+file:`, because nix's git fetcher cannot read a
# linked worktree's `.git` file. A fresh worktree holds only tracked files, so
# the copy is the same set `git+file:` would make.
worktree() {
  local sha=$2 dir="$out/src-$1"
  if [ ! -d "$dir" ]; then
    git -C "$checkout" worktree add --detach "$dir" "$sha" >&2
  fi
  echo "$dir"
}
cleanup() {
  for side in base head; do
    if [ -d "$out/src-$side" ]; then
      git -C "$checkout" worktree remove --force "$out/src-$side" || true
    fi
  done
}
trap cleanup EXIT

drv_paths() {
  nix eval --impure --json --expr \
    "(import $nix_file { flake = \"path:$1\"; }).drvPaths"
}

# One build at a time: an affected service crate depends on other affected
# crates, so two large compiles would otherwise share a review worker's memory.
build() {
  local side=$1 dir=$2
  if ! nix build --max-jobs 1 --impure --print-out-paths --out-link "$out/$side" --expr \
    "(import $nix_file { flake = \"path:$dir\"; roots = builtins.fromJSON (builtins.readFile $out/affected.json); }).report" \
    2>"$out/$side.log"; then
    status "failed: the $side build failed, see $out/$side.log"
    exit 1
  fi
}

base_dir=$(worktree base "$base_sha")
head_dir=$(worktree head "$head_sha")

if ! drv_paths "$base_dir" >"$out/base-drvs.json" 2>"$out/base.log"; then
  status "failed: evaluating base members failed, see $out/base.log"
  exit 1
fi
if ! drv_paths "$head_dir" >"$out/head-drvs.json" 2>"$out/head.log"; then
  status "failed: evaluating head members failed, see $out/head.log"
  exit 1
fi

jq -n --slurpfile base "$out/base-drvs.json" --slurpfile head "$out/head-drvs.json" '
  $head[0] | to_entries
  | map(select(.value != $base[0][.key])) | map(.key) | sort
' >"$out/affected.json"

if [ "$(jq length "$out/affected.json")" -eq 0 ]; then
  status "not_applicable: no Rust crate's derivation differs between $base_sha and $head_sha"
  exit 0
fi

# Base first: everything the two sides share is built here, and the head build
# finds it in the store.
build base "$base_dir"
build head "$head_dir"

if ! node --max-old-space-size=8192 "$diff_cli" "$out/base" "$out/head" "$out" 2>"$out/diff.log"; then
  status "failed: the comparison failed, see $out/diff.log"
  exit 1
fi
status compared
