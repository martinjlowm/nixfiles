{pkgs, ...}: let
  wezterm = pkgs.wezterm;

  mkWeztermScript = name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [wezterm];
      checkPhase = "";
      text = builtins.readFile ./${name}.sh;
    };
in {
  worktree = pkgs.writeShellApplication {
    name = "worktree";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.direnv
      pkgs.git
      pkgs.gnugrep
    ];
    checkPhase = "";
    text = builtins.readFile ./worktree.sh;
  };
  rmtree = pkgs.writeShellApplication {
    name = "rmtree";
    runtimeInputs = [
      pkgs.git
    ];
    checkPhase = "";
    text = builtins.readFile ./rmtree.sh;
  };
  loop = mkWeztermScript "loop";
  dependabot = mkWeztermScript "dependabot";
  project = mkWeztermScript "project";
  pr-maintenance = mkWeztermScript "pr-maintenance";
  github-issues = mkWeztermScript "github-issues";
  pr-ua = pkgs.writeShellApplication {
    name = "pr-ua";
    runtimeInputs = [
      pkgs.gh
      pkgs.jq
      pkgs.fzf
    ];
    checkPhase = "";
    text = builtins.readFile ./pr-ua.sh;
  };
  zendesk-ticket = pkgs.writeShellApplication {
    name = "zendesk-ticket";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    checkPhase = "";
    text = builtins.readFile ./zendesk-ticket.sh;
  };
}
