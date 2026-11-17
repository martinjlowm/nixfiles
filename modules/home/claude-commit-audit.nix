# Runs the comment-audit and scope-audit scorers on commits that Claude Code
# makes, in every repository. The hooks are config-based (`hook.<name>`), so
# git still runs each repository's own hooks directory after them, and
# `prek install` keeps working because core.hooksPath stays unset.
{pkgs, ...}: let
  commitAudit = pkgs.callPackage ../../config/claude/git-hooks {};
in {
  programs.git.settings.hook = {
    claude-comment-audit = {
      event = "pre-commit";
      command = "${commitAudit}/bin/claude-commit-audit comment";
    };
    claude-scope-audit = {
      event = "commit-msg";
      command = "${commitAudit}/bin/claude-commit-audit scope";
    };
  };
}
