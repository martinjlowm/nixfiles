# User configuration for martinjlowm
{
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;
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
      source = ../../sketchybar;
      recursive = true;
    };
  };
}
