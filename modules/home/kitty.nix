# Kitty terminal configuration
{pkgs, ...}: {
  programs.kitty = {
    enable = true;
    themeFile = "OneDark";
    environment = {
      "LS_COLORS" = "1";
    };
    shellIntegration = {
      enableZshIntegration = true;
    };
    font = {
      package = pkgs.nerd-fonts.hack;
      name = "Hack Nerd Font Mono Regular";
      size = 14;
    };
    settings = {
      macos_option_as_alt = true;
      cursor_shape = "block";
    };
  };
}
