# Download the published codegraph index for this repository, when there is one
# and it is newer than what the tree already has.
#
# The mj agent fleet reindexes on every merge to master and publishes
# <owner>/<name>/master/codegraph.db.zst plus a meta.json naming the commit it
# was built from. Indexing a repo the size of nest locally takes minutes;
# downloading it takes seconds, so no tree should ever build its own.
#
# Usage: codegraph-pull [--force]      (run anywhere inside the worktree)
#
# Exit codes:
#   0  the tree has an index — freshly downloaded, or already current
#   3  nothing to do here: this repo publishes no index, or there are no AWS
#      credentials. Callers treat 3 as "carry on without a graph".
#
# Idempotent by commit: re-running while the remote sha is unchanged does
# nothing, so it is safe to call on every worktree creation or from a wrapper.
BUCKET="${CODEGRAPH_INDEX_BUCKET:-mj-codegraph-index}"
# Repos the fleet publishes for. A repo that is not listed exits quietly: it is
# not expected to have an index, so a warning there would be noise.
PUBLISHED_REPOS="${CODEGRAPH_PUBLISHED_REPOS:-FactbirdHQ/nest}"

FORCE=""
[ "${1:-}" = "--force" ] && FORCE=1

say() { echo "codegraph-pull: $*" >&2; }

remote="$(git remote get-url origin 2>/dev/null || true)"
repo=""
for candidate in $PUBLISHED_REPOS; do
  case "$remote" in
    *"$candidate"*)
      repo="$candidate"
      break
      ;;
  esac
done
if [ -z "$repo" ]; then
  exit 3
fi

root="$(git rev-parse --show-toplevel)"
dir="$root/.codegraph"
marker="$dir/.published-sha"

# Checked up front so a missing login is one clear message, rather than an
# `aws s3 cp` error the caller has to interpret.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  say "no AWS credentials; skipping the published index for $repo"
  say "  log in and re-run, or build one locally with: codegraph init ."
  exit 3
fi

# Temp dir at the repo root, NOT inside .codegraph: a failed download must not
# leave an empty .codegraph behind, because that looks like "already indexed"
# to anything checking for the directory. Same filesystem as the final path, so
# installing the database is a rename.
tmp="$(mktemp -d "$root/.codegraph-pull.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

if ! aws s3 cp "s3://$BUCKET/$repo/master/meta.json" "$tmp/meta.json" >/dev/null 2>&1; then
  say "nothing published for $repo yet"
  exit 3
fi
sha="$(jq -r '.sha // empty' <"$tmp/meta.json")"

if [ -z "$FORCE" ] && [ -f "$dir/codegraph.db" ] && [ -n "$sha" ] &&
  [ "$sha" = "$(cat "$marker" 2>/dev/null || true)" ]; then
  say "index already current ($sha)"
  exit 0
fi

say "fetching index for $repo@${sha:-unknown}"
aws s3 cp "s3://$BUCKET/$repo/master/codegraph.db.zst" "$tmp/codegraph.db.zst" >&2
zstd -d --force -o "$tmp/codegraph.db" "$tmp/codegraph.db.zst" >/dev/null 2>&1

mkdir -p "$dir"
# Replaced by rename rather than written in place: a codegraph MCP server
# holding the old database keeps reading its own inode instead of observing a
# half-written file.
mv -f "$tmp/codegraph.db" "$dir/codegraph.db"
printf '%s\n' "$sha" >"$marker"

# The published index is master's. Sync folds in whatever this branch changed —
# incremental, so it walks the diff rather than reindexing. A failure here still
# leaves a usable master index, so it is a warning and not an error.
if ! codegraph sync "$root" >&2; then
  say "sync failed; keeping the master index as-is"
fi
