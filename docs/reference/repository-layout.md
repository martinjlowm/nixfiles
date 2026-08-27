# Repository layout

## Top level

| Path | Contents |
| --- | --- |
| `flake.nix` | Inputs, host configurations, `packages` and `devShells` outputs. |
| `bootstrap.sh` | Installs Determinate Nix when absent, then runs one flake package. |
| `lib/` | `mkPkgs`, `mkDarwinSystem`, `mkNixosSystem`, `nixpkgsConfig`. |
| `overlays/` | Package overrides and additions, including the sandboxed `claude-code` wrapper. |
| `modules/` | Configuration modules, split `darwin/`, `nixos/` and `home/`. |
| `hosts/` | Per-machine configuration. |
| `users/` | Per-user configuration. |
| `scripts/` | Shell sources and the derivations that wrap them. |
| `config/` | Files deployed verbatim into the home directory. |
| `specs/` | Spec files driving the agent loops. Contents are not tracked. |
| `.state/` | Loop working state. Gitignored. |
| `lockfiles/` | Pinned dependency manifests used by overlays. |
| `1password.nix` | opnix secret declarations. |
| `biome.json` | Biome configuration. |

## lib

`lib/default.nix` takes `inputs` and `overlays` and returns four attributes.

| Attribute | Signature | Notes |
| --- | --- | --- |
| `nixpkgsConfig` | attrset | Sets `allowUnfree`, `allowBroken`, `allowUnfreePredicate`, `allowUnsupportedSystem`. |
| `mkPkgs` | `{system, nixpkgs ? inputs.nixpkgs, extraOverlays ? []}` | Applies the opnix overlay and `overlays.default`. |
| `mkDarwinSystem` | `{system ? "aarch64-darwin", hostname, username, modules ? [], extraPkgs ? {}}` | Adds the home-manager Darwin module. Passes `nextPkgs`, `nextPkgsDevenv` and `nextPkgsClaude` through `specialArgs`. |
| `mkNixosSystem` | `{system ? "x86_64-linux", hostname, username, modules ? [], extraPkgs ? {}}` | Adds the home-manager NixOS module. Passes `nextPkgs` only. |

## modules

| Path | Modules |
| --- | --- |
| `modules/darwin/` | `jankyborders`, `linux-builder`, `packages`, `podman`, `signoz`, `system`, `yabai` |
| `modules/home/` | `claude-code`, `emacs`, `git`, `kitty`, `nushell`, `programs`, `tmux`, `wezterm`, `zsh` |
| `modules/nixos/` | `packages`, `system` |

Each directory has a `default.nix` importing its siblings.

## hosts

| Path | System | Notes |
| --- | --- | --- |
| `hosts/darwin/wololobook/` | `aarch64-darwin` | The only active machine. |
| `hosts/nixos/example/` | `x86_64-linux` | Template, including `hardware-configuration.nix`. Commented out in `flake.nix`. |

## Flake outputs

| Output | Value |
| --- | --- |
| `darwinConfigurations.wololobook` | The MacBook Pro configuration. |
| `darwinConfigurations."Martins-MacBook-Pro"` | Alias of the same configuration. |
| `nixosConfigurations` | Empty. |
| `darwinPackages` | `wololobook.pkgs`. |
| `packages.<system>` | The set described in [packages](packages.md). |
| `devShells.<system>.gh-image` | Shell providing `gh-with-image`. Also the default shell. |

`packages` and `devShells` are built for `aarch64-darwin`, `x86_64-darwin`, `aarch64-linux`
and `x86_64-linux`.

## Inputs

| Input | Tracks | Purpose |
| --- | --- | --- |
| `nixpkgs` | `nixos-26.05` | Base package set. |
| `nextNixpkgs` | pinned revision | Newer packages, exposed as `nextPkgs`. |
| `nextNixpkgsDevenv` | pinned revision | Newer devenv, exposed as `nextPkgsDevenv`. |
| `nextNixpkgsClaude` | pinned revision | Newer Claude Code, exposed as `nextPkgsClaude`. |
| `nix-darwin` | `nix-darwin-26.05` | macOS system layer. Follows `nixpkgs`. |
| `home-manager` | `release-26.05` | Home configuration. Follows `nixpkgs`. |
| `onepassword-secrets` | `brizzbuzz/opnix` | Secret material from 1Password. Follows `nixpkgs`. |
