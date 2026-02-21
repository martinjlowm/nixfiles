# Git configuration
{
  pkgs,
  nextPkgs,
  ...
}: let
  allowedSignersContent = pkgs.writeText "allowed_signers" ''
    martinjlowm@gmail.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILeNFTkHtufnDHSUoT1D3gfIKbpJjOTd1CQoBSrRYcz8
  '';
in {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Martin Jesper Low Madsen";
        email = "mj@factbird.com";
        signingKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILeNFTkHtufnDHSUoT1D3gfIKbpJjOTd1CQoBSrRYcz8";
      };
      alias = {
        stashgrep = ''!f() { for i in `git stash list --format="%gd"`; do git stash show -p $i | grep -H --label="$i" "$@"; done; }; f'';
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
      commit = {
        gpgsign = true;
      };
      gpg = {
        format = "ssh";
        ssh = {
          program = "${nextPkgs._1password-gui}/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
          allowedSignersFile = "${allowedSignersContent}";
        };
      };
    };
  };

  programs.git-worktree-switcher.enable = true;

  programs.gh.enable = true;
}
