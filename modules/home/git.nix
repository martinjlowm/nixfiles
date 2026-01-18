# Git configuration
_: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Martin Jesper Low Madsen";
        email = "mj@factbird.com";
      };
      alias = {
        stashgrep = ''
            !f() {
            for i in `git stash list --format=\"%gd\"`; do
              git stash show -p $i | grep -H --label=\"$i\" \"$@\";
            done;
          };
          f
        '';
      };
      core = {
        ignorecase = false;
      };
      push = {
        autoSetupRemote = true;
      };
      pull = {
        rebase = false;
      };
    };
  };

  programs.git-worktree-switcher.enable = true;

  programs.gh.enable = true;
}
