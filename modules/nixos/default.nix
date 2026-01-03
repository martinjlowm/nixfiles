# Default NixOS module - imports all NixOS-specific modules
{...}: {
  imports = [
    ./system.nix
    ./packages.nix
  ];
}
