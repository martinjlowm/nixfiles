RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CLEAR="\033[0m"
VERBOSE=

function usage {
  cat <<EOF
      worktree [-v] <branch name>

    create a git worktree with <branch name>. Will create a worktree if one isn't
    found that matches the given name.

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
  dirname=''${branchname//\//_}

  # pull the most recent version of the remote
  if ! git pull; then
    warn "Unable to run git pull, there may not be an upstream"
  fi

  # if the branch name already exists, we want to check it out. Otherwise,
  # create a new branch. I'm sure there's probably a way to do that in one
  # command, but I'm done fiddling with git at this point
  #
  # As far as I can tell, we have to check locally and remotely separately if
  # we want to be accurate. See https://stackoverflow.com/a/75040377 for the
  # reasoning here. Also this has some caveats, but probably works well
  # enough :shrug:
  #
  # if the branch exists locally:
  if git for-each-ref --format='%(refname:lstrip=2)' refs/heads | grep -E "^$branchname$" > /dev/null 2>&1; then
    if ! git worktree add "../$dirname" "$branchname"; then
      die "failed to create git worktree $branchname"
    fi
    # if the branch exists on a remote:
  elif git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -E "^$branchname$" > /dev/null 2>&1; then
    if ! git worktree add "../$dirname" "$branchname"; then
      die "failed to create git worktree $branchname"
    fi
  else
    # otherwise, create a new branch
    if ! git worktree add -b "$branchname" "../$dirname"; then
      die "failed to create git worktree $branchname"
    fi
  fi

  # Find untracked files that we want to copy to the new worktree

  # Copy over Yarn cache, unplugged and install-state.gz
  if [ -d ".yarn/cache" ]; then
    cp_cow .yarn/cache ../"$dirname"/.yarn/cache
  fi
  if [ -d ".yarn/unplugged" ]; then
    cp_cow .yarn/unplugged ../"$dirname"/.yarn/unplugged
  fi
  if [ -f ".yarn/install-state.gz" ]; then
    cp_cow .yarn/install-state.gz ../"$dirname"/.yarn/install-state.gz
  fi

  # Copy over Rust builds
  if [ -d "target" ]; then
    cp_cow target ../"$dirname"/target
  fi

  # Copy over NAPI-generated symlinks
  while IFS= read -r link_path; do
    mkdir -p "$(dirname "../$dirname/$link_path")"
    cp_cow "$link_path" "../$dirname/$link_path" > /dev/null
  done < <(find . -type l -lname "$(git rev-parse --show-toplevel)/target/*")

  # Copy over Nix-generated symlinks
  while IFS= read -r link_path; do
    mkdir -p "$(dirname "../$dirname/$link_path")"
    cp_cow "$link_path" "../$dirname/$link_path" > /dev/null
  done < <(find . -type l -lname '/nix/store/*')

  # if there was an envrc file, tell direnv that it's ok to run it
  if [ -f "../$dirname/.envrc" ]; then
    direnv allow "../$dirname"
  fi

  # now change to the new tree and enable the root envrc if present
  cd "../$dirname" || return
  printf "%bcreated worktree %s%b\n" "$GREEN" "../$dirname" "$CLEAR"
}

while true; do
  case $1 in
    help | -h | --help)
      usage
      ;;
    -v | --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

_worktree "$@"
