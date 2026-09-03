# Common home-manager programs
{pkgs, ...}: {
  programs.starship = {
    enable = true;
    settings = {
      time.disabled = false;
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {
      global = {
        hide_env_diff = true;
      };
    };
  };

  programs.ripgrep.enable = true;
  programs.awscli.enable = true;
  programs.dircolors.enable = true;
  programs.dircolors.enableZshIntegration = true;

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

  # home-manager ships no module for aws-sso-cli, so the `a` and `c` functions
  # in zsh.nix are the shell integration. The package sits here for the
  # commands they do not wrap: `aws-sso login`, `aws-sso cache`, and the zsh
  # completions the derivation installs. overlays/default.nix pins it past the
  # ListAccounts page-size bug in the nixpkgs version.
  home.packages = [pkgs.aws-sso-cli];

  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      tuttieee.emacs-mcx
      tiehuis.zig
      rust-lang.rust-analyzer
      kahole.magit
      graphql.vscode-graphql
    ];
  };
}
