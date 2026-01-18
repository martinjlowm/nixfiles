# Default home-manager module - imports common modules
{...}: {
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
