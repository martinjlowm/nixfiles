# Default home-manager module - imports common modules
{pkgs, ...}: {
  home.packages = with pkgs; [tree];

  imports = [
    ./claude-code.nix
    ./zsh.nix
    ./nushell.nix
    ./git.nix
    ./tmux.nix
    ./kitty.nix
    ./wezterm.nix
    ./programs.nix
  ];
}
