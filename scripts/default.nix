{pkgs, ...}: let
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
in [
  worktree
  rmtree
  (pkgs.writeShellScriptBin "loop" (builtins.readFile ./loop.sh))
  (pkgs.writeShellScriptBin "dependabot" (builtins.readFile ./dependabot.sh))
  (pkgs.writeShellScriptBin "project" (builtins.readFile ./project.sh))
  (pkgs.writeShellScriptBin "pr-maintenance" (builtins.readFile ./pr-maintenance.sh))
  (pkgs.writeShellScriptBin "github-issues" (builtins.readFile ./github-issues.sh))
]
