# Host configuration for wololobook (MacBook)
{
  inputs,
  pkgs,
  nextPkgs,
  hostname,
  username,
  ...
}: {
  imports = [
    ../../../modules/darwin
  ];

  # Host-specific overrides
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Enable sketchybar on this host
  services.sketchybar.enable = true;

  # Configure home-manager for this user
  home-manager.users.${username} = import ../../../users/martinjlowm;

  # 1Password configuration
  programs._1password = {
    enable = true;
    package = nextPkgs._1password-cli;
  };
  programs._1password-gui = {
    enable = true;
    package = nextPkgs._1password-gui;
  };
}
