# User configuration for martinjlowm
{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
  username = "martinjlowm";
in {
  imports = [
    ../../modules/home
    ../../modules/home/emacs.nix
  ];

  home.homeDirectory = lib.mkForce (
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}"
  );
  home.stateVersion = "22.05";

  # Darwin-specific files
  home.file = lib.optionalAttrs isDarwin {
    ".config/sketchybar" = {
      source = ../../config/sketchybar;
      recursive = true;
    };
    # The 1Password SSH agent offers keys only from the vaults listed here.
    ".config/1Password/ssh/agent.toml".text = ''
      [[ssh-keys]]
      vault = "Personal"

      [[ssh-keys]]
      vault = "Developer"

      [[ssh-keys]]
      vault = "Factbird"
    '';
  };
}
