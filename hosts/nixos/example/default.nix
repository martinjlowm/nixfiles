# Example NixOS host configuration
# Copy this directory and customize for your Linux machine
{
  pkgs,
  nextPkgs,
  hostname,
  username,
  ...
}: {
  imports = [
    ../../../modules/nixos
    # Include your hardware-configuration.nix here:
    # ./hardware-configuration.nix
  ];

  # Boot loader configuration (adjust for your system)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Configure home-manager for this user
  home-manager.users.${username} = {pkgs, ...}: {
    imports = [
      ../../../modules/home
      # Note: emacs module may need adjustment for Linux
    ];

    home.homeDirectory = "/home/${username}";
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
