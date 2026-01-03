# Emacs configuration (cross-platform)
{
  pkgs,
  lib,
  ...
}: let
  isDarwin = pkgs.stdenv.isDarwin;

  # Use emacs-macport on macOS, regular emacs on Linux
  emacs =
    if isDarwin
    then pkgs.emacs-macport
    else pkgs.emacs;

  allGrammars = (pkgs.emacsPackagesFor emacs).treesit-grammars.with-all-grammars;
  emacs-with-packages = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs:
    with epkgs; [
      pkgs.mu
      vterm
      multi-vterm
      pdf-tools
      allGrammars
      claude-shell
    ]);
in {
  home.file.".config/emacs/.local/cache/tree-sitter".source = "${allGrammars}/lib";

  programs.emacs = {
    enable = true;
    package = emacs-with-packages;
  };
}
