# Default Darwin module - imports all Darwin-specific modules
{...}: {
  imports = [
    ./system.nix
    ./packages.nix
    ./yabai.nix
    ./jankyborders.nix
    ./linux-builder.nix
  ];
}
