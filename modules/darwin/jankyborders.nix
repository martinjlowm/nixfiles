# JankyBorders window border configuration for macOS
{pkgs, ...}: {
  services.jankyborders = {
    package = pkgs.jankyborders.overrideAttrs {
      src = pkgs.fetchFromGitHub {
        owner = "FelixKratz";
        repo = "JankyBorders";
        rev = "v1.8.4";
        hash = "sha256-31Er+cUQNJbZnXKC6KvlrBhOvyPAM7nP3BaxunAtvWg=";
      };
    };
    enable = true;
    active_color = "0xFFFF00CC";
    inactive_color = "";
    width = 6.0;
  };
}
