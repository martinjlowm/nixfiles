#!/usr/bin/env bash
set -euo pipefail

FLAKE="github:martinjlowm/nixfiles"

usage() {
  cat <<EOF
Usage: curl -fsSL <url>/bootstrap.sh | bash -s -- <package> [args...]

Installs Determinate Nix (if needed) and runs a flake package.

Packages:
  dependabot, fix, loop, project, pr-maintenance, pr-review,
  github-issues, claude-code, worktree, rmtree, tech-spec, ...

Examples:
  curl -fsSL <url>/bootstrap.sh | bash -s -- dependabot
  curl -fsSL <url>/bootstrap.sh | bash -s -- fix 123
  curl -fsSL <url>/bootstrap.sh | bash -s -- claude-code
EOF
  exit 1
}

PACKAGE="${1:-}"
if [ -z "$PACKAGE" ]; then
  usage
fi
shift

# Ensure Nix is available
ensure_nix() {
  if command -v nix >/dev/null 2>&1; then
    return
  fi

  # Check common profile locations
  for p in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
           "$HOME/.nix-profile/etc/profile.d/nix.sh" \
           "$HOME/.local/state/nix/profiles/profile/etc/profile.d/nix-daemon.sh"; do
    if [ -f "$p" ]; then
      # shellcheck disable=SC1090
      . "$p"
      if command -v nix >/dev/null 2>&1; then
        return
      fi
    fi
  done

  echo "Nix not found. Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

  # Source the newly installed Nix
  for p in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
           "$HOME/.nix-profile/etc/profile.d/nix.sh" \
           "$HOME/.local/state/nix/profiles/profile/etc/profile.d/nix-daemon.sh"; do
    if [ -f "$p" ]; then
      # shellcheck disable=SC1090
      . "$p"
      break
    fi
  done

  if ! command -v nix >/dev/null 2>&1; then
    echo "Error: Nix installation succeeded but nix not found in PATH." >&2
    echo "Try opening a new shell and running: nix run ${FLAKE}#${PACKAGE}" >&2
    exit 1
  fi
}

ensure_nix

exec nix run "${FLAKE}#${PACKAGE}" -- "$@"
