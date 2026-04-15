{ config, lib, pkgs, ... }:

let
  cfg = config.services.podman;

  initScript = pkgs.writeShellScript "podman-init" ''
    export PATH="${pkgs.podman}/bin:$PATH"

    if ! podman machine inspect podman-machine-default &>/dev/null; then
      podman machine init --cpus 4 --memory 8192 --volume /nix/store:/nix/store:ro
    fi

    if [ "$(podman machine inspect podman-machine-default | ${pkgs.jq}/bin/jq -r '.[0].State')" != "running" ]; then
      podman machine start
    fi
  '';
in
{
  options.services.podman = {
    enable = lib.mkEnableOption "Podman machine initialization";
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.podman-init = {
      serviceConfig = {
        Label = "org.podman.machine-init";
        ProgramArguments = [ "${initScript}" ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/podman-init.log";
        StandardErrorPath = "/tmp/podman-init.log";
      };
    };
  };
}
