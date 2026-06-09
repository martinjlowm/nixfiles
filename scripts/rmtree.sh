# Pulled from https://github.com/llimllib/personal_code/blob/daab9eb1/homedir/.local/bin/rmtree

# LICENSE: unlicense. This is free and unencumbered software released into the public domain.
# see unlicense.org for full license

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CLEAR="\033[0m"
VERBOSE=

function usage {
  cat <<"EOF"
    rmtree [-vh] <worktree name> [worktree name...]

    Remove a worktree from a git repository by name. Can be run from any
    worktree or the bare repository directory.

    Use 'rmtree --list' to see available worktrees.

    FLAGS:

        -h, --help:    print this help
        -v, --verbose: verbose mode
        -l, --list:    list all worktrees
EOF
  exit 1
}

function die {
  if [ -n "$VERBOSE" ]; then
    set +x
  fi
  printf '%b%s%b\n' "$RED" "$1" "$CLEAR"
  exit 1
}

function err {
  printf '%b%s%b\n' "$YELLOW" "$1" "$CLEAR"
}

function warn {
  printf '%b%s%b\n' "$YELLOW" "$1" "$CLEAR"
}

function list_worktrees {
  echo "Available worktrees:"
  git worktree list --porcelain | grep "^worktree " | sed 's/^worktree /  /'
}

# rmtree <name> will find the worktree by name, remove it, and delete the branch
function rmtree {
  if [ -n "$VERBOSE" ]; then
    set -x
  fi

  if [ -z "$1" ]; then
    die "You must provide a worktree name to remove. Use --list to see available worktrees."
  fi

  # for each argument, find and delete the worktree
  while [ $# -gt 0 ]; do
    # Replace slashes with underscores to match worktree.sh naming convention
    treename="${1//\//_}"

    # Find worktree path by matching the basename from porcelain output
    WORKTREE_PATH=$(git worktree list --porcelain | grep "^worktree " | sed 's/^worktree //' | grep "/${treename}$")

    if [ -z "$WORKTREE_PATH" ]; then
      err "Worktree '$treename' not found, skipping"
      list_worktrees
      shift
      continue
    fi

    # Get branch name from the worktree
    branch_name=$(git worktree list --porcelain | grep -A2 "^worktree ${WORKTREE_PATH}$" | grep "^branch " | sed 's/^branch refs\/heads\///')

    warn "Removing worktree: $treename (branch: $branch_name)"

    # Stop a lingering codegraph daemon first: it would keep serving the
    # deleted index from memory, and a later re-init in a same-named tree
    # would silently query stale data until the daemon dies.
    pidfile="$WORKTREE_PATH/.codegraph/daemon.pid"
    if [ -f "$pidfile" ]; then
      daemon_pid=$(jq -r '.pid // empty' "$pidfile" 2>/dev/null)
      if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
        warn "Stopping codegraph daemon (pid $daemon_pid)"
        kill "$daemon_pid" 2>/dev/null || true
      fi
    fi

    # Remove the worktree (this also removes the directory)
    if ! git worktree remove "$WORKTREE_PATH"; then
      err "Failed to remove worktree, trying force removal..."
      git worktree remove --force "$WORKTREE_PATH" || die "Failed to remove worktree $treename"
    fi

    # Delete the branch if it exists
    if [ -n "$branch_name" ]; then
      if git branch -D "$branch_name" 2>/dev/null; then
        printf '%bDeleted branch: %s%b\n' "$GREEN" "$branch_name" "$CLEAR"
      else
        warn "Could not delete branch $branch_name (may be checked out elsewhere or already deleted)"
      fi
    fi

    shift
  done
}

while [ $# -gt 0 ]; do
  case $1 in
    help | -h | --help)
      usage
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -l | --list)
      list_worktrees
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

rmtree "$@"
