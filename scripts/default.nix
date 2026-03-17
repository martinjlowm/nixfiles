{pkgs, ...}: let
  wezterm = pkgs.wezterm;

  mkWeztermScript = name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [wezterm];
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
    text = builtins.readFile ./worktree.sh;
  };
  rmtree = pkgs.writeShellApplication {
    name = "rmtree";
    runtimeInputs = [
      pkgs.git
    ];
    text = builtins.readFile ./rmtree.sh;
  };
  loop = mkWeztermScript "loop";
  dependabot = mkWeztermScript "dependabot";
  project = mkWeztermScript "project";
  pr-maintenance = mkWeztermScript "pr-maintenance";
  github-issues = mkWeztermScript "github-issues";
}
