# Yabai window manager configuration for macOS
{
  pkgs,
  nextPkgsDevenv,
  lib,
  ...
}: let
  yabai = "${nextPkgsDevenv.yabai}/bin/yabai";
  jq = "${pkgs.jq}/bin/jq";

  yabai-docked = pkgs.writers.writeBashBin "yabai-docked" ''
    ${yabai} -m rule --apply app="^Slack" display="1"

    ${yabai} -m rule --apply app="^Emacs$" display="2"
    ${yabai} -m rule --apply app="^Terminal$" display="2"

    emacs=$(${yabai} -m query --windows  | ${jq} '.[] | select(.title | contains("Emacs")) | .id' | tr -d '\n')
    ${yabai} -m window $emacs --swap west

    ${yabai} -m rule --apply app="^Brave Browser$" display="3"
    ${yabai} -m rule --apply app="^Brave Browser$" title="YouTube" display="3"

    youtube=$(${yabai} -m query --windows  | ${jq} '.[] | select(.title | contains("YouTube")) | .id' | tr -d '\n')
    if [ ! -z $youtube ]; then
      ${yabai} -m window $youtube --swap west
      ${yabai} -m window $youtube --resize bottom_right:-700:0
    fi

    firefox=$(${yabai} -m query --windows  | ${jq} '.[] | select(.title | contains("Firefox")) | .id' | tr -d '\n')
    if [ ! -z $firefox ]; then
      ${yabai} -m rule --apply app="^Firefox$" display="3"
      ${yabai} -m window $firefox --warp east
    fi
  '';

  yabai-undocked = pkgs.writers.writeBashBin "yabai-undocked" ''
    ${yabai} -m rule --apply app="^Terminal$" display="1"
    ${yabai} -m rule --apply app="^Emacs$" display="1"
  '';
in {
  environment.systemPackages = [
    yabai-docked
    yabai-undocked
  ];

  services.yabai = {
    enable = true;
    package = nextPkgsDevenv.yabai;
    config = {
      layout = "bsp";
      top_padding = 8;
      bottom_padding = 8;
      left_padding = 8;
      right_padding = 8;
      window_gap = 8;
    };
    extraConfig = ''
      yabai -m rule --add app="System Settings" manage=off

      numDisplays=$(yabai -m query --displays | ${jq} '. | length')
      if [[ $numDisplays == "3" ]]; then
        ${yabai-docked}/bin/yabai-docked
      else
        ${yabai-undocked}/bin/yabai-undocked
      fi

      yabai -m signal --add event=display_added action="${yabai-docked}/bin/yabai-docked"
      yabai -m signal --add event=display_removed action="${yabai-undocked}/bin/yabai-undocked"
    '';
  };
}
