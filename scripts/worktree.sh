RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CLEAR="\033[0m"
VERBOSE=
BASE_BRANCH=

function usage {
  cat <<EOF
      worktree [-v] [-b <base>] <branch name>

    Create a git worktree with <branch name>. Will create a worktree if one isn't
    found that matches the given name.

    FLAGS:
        -v, --verbose     Verbose mode
        -b, --base <ref>  Base branch/ref to branch off of (default: origin/master or origin/main)

    Will copy over any .env, .envrc, or .tool-versions files to the new worktree
EOF
  kill -INT $$
}

function die {
  printf '%b%s%b\n' "$RED" "$1" "$CLEAR"
  # exit the script, but if it was sourced, don't kill the shell
  kill -INT $$
}

function warn {
  printf '%b%s%b\n' "$YELLOW" "$1" "$CLEAR"
}

# If at all possible, use copy-on-write to copy files. This is especially
# important to allow us to copy node_modules directories efficiently
#
# I tried to figure out how to actually determine the filesystem support for
# copy-on-write, but did not find any good references, so I'm falling back on
# "try and see if it fails"
function cp_cow {
  if [ ! -e "$1" ] ; then
    return;
  fi

  if ! cp -R --reflink "$1" "$2"; then
    warn "Unable to copy file $1 to $2 - folder may not exist"
  fi
}


# Create a worktree from a given branchname, in exactly the way I like it.
function _worktree {
  if [ -z "$1" ]; then
    usage
  fi

  if [ -n "$VERBOSE" ]; then
    set -x
  fi
  branchname="$1"

  # Replace slashes with underscores. If there's no slash, dirname will equal
  # branchname. So "alu/something-other" becomes "alu_something-other", but
  # "quick-fix" stays unchanged
  # https://www.tldp.org/LDP/abs/html/parameter-substitution.html
  treename=''${branchname//\//_}

  # Get the base directory for worktrees (parent of git common dir)
  # This works for both regular repos and bare repos
  GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
  WORKTREE_BASE="$(dirname "$GIT_COMMON_DIR")"
  WORKTREE_PATH="$WORKTREE_BASE/$treename"

  # Fetch the most recent version of the remote
  if ! git fetch; then
    warn "Unable to run git fetch, there may not be an upstream"
  fi

  # Determine the base branch to branch off of
  if [ -n "$BASE_BRANCH" ]; then
    # Use specified base branch
    if ! git rev-parse --verify "$BASE_BRANCH" > /dev/null 2>&1; then
      die "Base branch '$BASE_BRANCH' does not exist"
    fi
    MAIN_BRANCH="$BASE_BRANCH"
  elif git rev-parse --verify origin/master > /dev/null 2>&1; then
    MAIN_BRANCH="origin/master"
  elif git rev-parse --verify origin/main > /dev/null 2>&1; then
    MAIN_BRANCH="origin/main"
  else
    MAIN_BRANCH="HEAD"
    warn "Could not find origin/master or origin/main, using HEAD"
  fi

  # Determine the master worktree path for copying files
  # Try master first, then main
  if [ -d "$WORKTREE_BASE/master" ]; then
    MASTER_WORKTREE="$WORKTREE_BASE/master"
  elif [ -d "$WORKTREE_BASE/main" ]; then
    MASTER_WORKTREE="$WORKTREE_BASE/main"
  else
    MASTER_WORKTREE=""
  fi

  # if the branch name already exists, we want to check it out. Otherwise,
  # create a new branch based off the main branch.
  #
  # As far as I can tell, we have to check locally and remotely separately if
  # we want to be accurate. See https://stackoverflow.com/a/75040377 for the
  # reasoning here.
  #
  # if the branch exists locally:
  if git for-each-ref --format='%(refname:lstrip=2)' refs/heads | grep -E "^$branchname$" > /dev/null 2>&1; then
    if ! git worktree add "$WORKTREE_PATH" "$branchname"; then
      die "failed to create git worktree $branchname"
    fi
    # if the branch exists on a remote:
  elif git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -E "^$branchname$" > /dev/null 2>&1; then
    if ! git worktree add "$WORKTREE_PATH" "$branchname"; then
      die "failed to create git worktree $branchname"
    fi
  else
    # otherwise, create a new branch based off the main branch
    if ! git worktree add -b "$branchname" "$WORKTREE_PATH" "$MAIN_BRANCH"; then
      die "failed to create git worktree $branchname"
    fi
  fi

  # Copy files from master worktree if it exists
  if [ -n "$MASTER_WORKTREE" ]; then
    # Copy over Yarn cache, unplugged and install-state.gz
    if [ -d "$MASTER_WORKTREE/.yarn/cache" ]; then
      mkdir -p "$WORKTREE_PATH/.yarn/cache"
      cp_cow "$MASTER_WORKTREE/.yarn/cache" "$WORKTREE_PATH/.yarn/cache"
    fi
    if [ -d "$MASTER_WORKTREE/.yarn/unplugged" ]; then
      mkdir -p "$WORKTREE_PATH/.yarn/unplugged"
      cp_cow "$MASTER_WORKTREE/.yarn/unplugged" "$WORKTREE_PATH/.yarn/unplugged"
    fi
    if [ -f "$MASTER_WORKTREE/.yarn/install-state.gz" ]; then
      cp_cow "$MASTER_WORKTREE/.yarn/install-state.gz" "$WORKTREE_PATH/.yarn/install-state.gz"
    fi

    # Copy over Nix-generated symlinks
    while IFS= read -r link_path; do
      mkdir -p "$(dirname "$WORKTREE_PATH/$link_path")"
      cp_cow "$MASTER_WORKTREE/$link_path" "$WORKTREE_PATH/$link_path" > /dev/null
    done < <(cd "$MASTER_WORKTREE" && find . -type l -lname '/nix/store/*')
  fi

  # if there was an envrc file, tell direnv that it's ok to run it
  if [ -f "$WORKTREE_PATH/.envrc" ]; then
    echo "Running direnv allow..."
    direnv allow "$WORKTREE_PATH"
  fi

  # Change to the new worktree for post-setup commands
  cd "$WORKTREE_PATH" || return

  # Run package manager install and just recipes in the background
  # yarn install runs in parallel with (just codegen && just write-schema)
  PIDS=()

  # Run package manager install if available (in background)
  if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    echo "Running bun install in background..."
    (bun install || warn "bun install failed") &
    PIDS+=($!)
  elif [ -f "yarn.lock" ]; then
    echo "Running yarn install in background..."
    (yarn install || warn "yarn install failed") &
    PIDS+=($!)
  elif [ -f "package-lock.json" ]; then
    echo "Running npm install in background..."
    (npm install || warn "npm install failed") &
    PIDS+=($!)
  elif [ -f "package.json" ]; then
    # Fallback: package.json exists but no lockfile, try yarn
    echo "Running yarn install in background..."
    (yarn install || warn "yarn install failed") &
    PIDS+=($!)
  fi

  # Run just recipes if available (in background, sequentially)
  if command -v just > /dev/null 2>&1 && [ -f "justfile" ] || [ -f "Justfile" ]; then
    HAS_CODEGEN=$(just --list 2>/dev/null | grep -q "codegen" && echo "1" || echo "")
    HAS_WRITE_SCHEMA=$(just --list 2>/dev/null | grep -q "write-schema" && echo "1" || echo "")

    if [ -n "$HAS_CODEGEN" ] || [ -n "$HAS_WRITE_SCHEMA" ]; then
      echo "Running just codegen and write-schema in background..."
      (
        if [ -n "$HAS_CODEGEN" ]; then
          just codegen || warn "just codegen failed"
        fi
        if [ -n "$HAS_WRITE_SCHEMA" ]; then
          just write-schema || warn "just write-schema failed"
        fi
      ) &
      PIDS+=($!)
    fi
  fi

  # Wait for all background processes to complete
  for PID in "${PIDS[@]}"; do
    wait "$PID"
  done

  printf "%bcreated worktree %s%b\n" "$GREEN" "$WORKTREE_PATH" "$CLEAR"
}

POSITIONAL_ARGS=()
while [ $# -gt 0 ]; do
  case $1 in
    help | -h | --help)
      usage
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    -b | --base)
      BASE_BRANCH="$2"
      shift 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL_ARGS[@]}"

_worktree "$@"
