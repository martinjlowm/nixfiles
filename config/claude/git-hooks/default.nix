# The commit-audit hook, built with `callPackage` by modules/home and by the
# factbird-factory agent image, so a laptop commit and a fleet commit run the
# same scorers.
{
  writeShellApplication,
  git,
  nodejs,
  coreutils,
}:
writeShellApplication {
  name = "claude-commit-audit";
  runtimeInputs = [git nodejs coreutils];
  text = ''
    COMMENT_SCORER=${../skills/comment-audit/scripts}/comment-score.ts
    SCOPE_SCORER=${../skills/scope-audit/scripts}/scope-score.ts
    ${builtins.readFile ./commit-audit.sh}
  '';
}
