# ZSH shell configuration (cross-platform)
{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  programs.nushell = {
    enable = true;

    shellAliases =
      {
        ls = "ls -Gal";
        sl = "ls";
        extract-mp3 = "${pkgs.yt-dlp}/bin/yt-dlp --extract-audio --audio-format mp3 --audio-quality 0";
        keyfinder = "${pkgs.keyfinder-cli}/bin/keyfinder-cli";
        localhost = ''sed -E "s#(https://)([^/]+)#\\1localhost:3000#"'';
        wget = "curl -O --retry 999 --retry-max-time 0 -C -";
        worktree = "source worktree";
        just = "$env.HOME/.cargo/bin/just";
      }
      // lib.optionalAttrs isDarwin {
        rebuild = "darwin-rebuild switch --flake ~/.config/nix-darwin -L";
        emacs = "${pkgs.emacs-macport}/Applications/Emacs.app/Contents/MacOS/Emacs";
      }
      // lib.optionalAttrs (!isDarwin) {
        rebuild = "sudo nixos-rebuild switch --flake ~/.config/nixos -L";
      };

    environmentVariables = {
      DEVENV_ENABLE_HOOKS = "true";
      DEVENV_ENABLE_MCP_SENTRY = "true";
      DEVENV_ENABLE_MCP_NOTION = "true";
      DEVENV_ENABLE_MCP_SERENA = "true";
      DEVENV_ENABLE_MCP_AWS_DIAGRAM = "true";
      DOCKER_HOST = "unix:///tmp/podman/podman-machine-default-api.sock";
      NIXPKGS_ALLOW_UNFREE = 1;
    };
  };
}
