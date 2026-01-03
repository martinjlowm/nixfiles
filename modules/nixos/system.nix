# NixOS system defaults and settings
{
  hostname,
  username,
  ...
}: {
  networking.hostName = hostname;

  # Enable Nix flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["root" "@wheel"];

  # Default locale
  i18n.defaultLocale = "en_US.UTF-8";

  # Time zone (adjust as needed)
  time.timeZone = "Europe/Copenhagen";

  # Enable networking
  networking.networkmanager.enable = true;

  # Create the user
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "docker"];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
