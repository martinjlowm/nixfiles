# Common home-manager programs
{
  pkgs,
  nextPkgs,
  ...
}: {
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
  programs.wezterm.enable = true;
  programs.wezterm.enableZshIntegration = true;

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.granted = {
    enable = true;
    enableZshIntegration = true;
    package = nextPkgs.granted;
  };

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
