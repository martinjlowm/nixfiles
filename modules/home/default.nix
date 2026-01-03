# Default home-manager module - imports common modules
{...}: {
  imports = [
    ./zsh.nix
    ./git.nix
    ./tmux.nix
    ./kitty.nix
    ./programs.nix
  ];
}
