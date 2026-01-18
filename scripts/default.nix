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
]
