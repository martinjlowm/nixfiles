# `rebuild` is a system package rather than the shell alias it used to be,
# because `darwin-rebuild switch` has to run as root. Under `sudo` this script
# gets root's PATH, which contains no home-manager alias and no
# ~/.nix-profile/bin, and root's HOME, which is /var/root and holds no clone of
# this flake. So the flake path is worked out from the two things sudo does
# preserve: the working directory and $SUDO_USER.

# darwin-rebuild and nix live here. Root's PATH under sudo is assembled without
# sourcing the nix-darwin shell files, so name the directory rather than trust
# it to already be on PATH.
PATH=$PATH:/run/current-system/sw/bin

# Home of the account that called sudo. $HOME is root's.
caller_home () {
  if [[ -n ${SUDO_USER:-} ]]; then
    dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | cut -d' ' -f2
  else
    printf '%s\n' "$HOME"
  fi
}

# The flake to build: the repository the caller is standing in, or the clone
# the tutorial makes when the caller is standing somewhere else.
find_flake () {
  local dir=$PWD
  while [[ $dir != / ]]; do
    if [[ -f $dir/flake.nix && -d $dir/hosts ]]; then
      printf '%s\n' "$dir"
      return
    fi
    dir=$(dirname "$dir")
  done
  printf '%s\n' "$(caller_home)/projects/nixfiles"
}

flake=$(find_flake)
if [[ ! -f $flake/flake.nix ]]; then
  echo "rebuild: no flake.nix in $PWD or above it, and none at $flake" >&2
  exit 1
fi

# A first argument that is not a flag names the darwin-rebuild subcommand, so
# `rebuild build` checks without activating. Flags pass through untouched.
action=switch
if (($# > 0)) && [[ $1 != -* ]]; then
  action=$1
  shift
fi

# Both `wololobook` and `Martins-MacBook-Pro` are defined, so whichever name
# the machine answers to resolves.
exec darwin-rebuild "$action" --flake "$flake#$(hostname -s)" -L "$@"
