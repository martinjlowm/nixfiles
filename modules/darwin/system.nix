# macOS system defaults and settings
{
  config,
  lib,
  pkgs,
  hostname,
  username,
  ...
}: {
  networking.hostName = hostname;

  system.primaryUser = username;

  # Keyboard settings
  system.defaults.NSGlobalDomain.KeyRepeat = 2;
  system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
  system.defaults.NSGlobalDomain._HIHideMenuBar = true;
  system.defaults.NSGlobalDomain."com.apple.keyboard.fnState" = true;
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToControl = true;

  # Dock settings
  system.defaults.dock.orientation = "right";
  system.defaults.dock.autohide = true;
  system.defaults.dock.wvous-tl-corner = 11;

  # Security - Touch ID for sudo
  security.pam.services.sudo_local.enable = true;
  security.pam.services.sudo_local.reattach = true;
  security.pam.services.sudo_local.touchIdAuth = true;

  # Key remapping launchd agent
  launchd.user.agents.remap-keys = {
    serviceConfig = {
      ProgramArguments = [
        "/usr/bin/hidutil"
        "property"
        "--set"
        ''
          {
            "UserKeyMapping":[
              {"HIDKeyboardModifierMappingSrc":0x700000035,"HIDKeyboardModifierMappingDst":0x700000064},
              {"HIDKeyboardModifierMappingSrc":0x700000064,"HIDKeyboardModifierMappingDst":0x700000035}
            ]
          }
        ''
      ];
      RunAtLoad = true;
    };
  };

  programs.zsh.enable = true;

  system.stateVersion = 4;

  # All nerd fonts
  fonts.packages = [] ++ builtins.filter pkgs.lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

  nix.enable = false;
  nix.settings.trusted-users = ["@admin"];
}
