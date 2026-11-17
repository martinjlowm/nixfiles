# Default home-manager module - imports common modules
{pkgs, ...}: {
  home.packages = with pkgs; [tree];

  imports = [
    ./aws-sso.nix
    ./claude-code.nix
    ./claude-commit-audit.nix
    ./zsh.nix
    ./nushell.nix
    ./git.nix
    ./tmux.nix
    ./kitty.nix
    ./wezterm.nix
    ./programs.nix
  ];
}
