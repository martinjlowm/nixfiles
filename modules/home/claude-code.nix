# Claude Code configuration
{
  nextPkgs,
  nextPkgsClaude,
  lib,
  ...
}: let
  claudeDirectory = ../../config/claude;
  stripMdExt = name: lib.removeSuffix ".md" name;
in {
  programs.claude-code = {
    enable = true;
    package = nextPkgsClaude.claude-code;
    agents = builtins.listToAttrs (builtins.map (name: {
        name = stripMdExt name;
        value = claudeDirectory + "/agents/${name}";
      })
      (builtins.attrNames (builtins.readDir "${claudeDirectory}/agents")));
    commands = builtins.listToAttrs (builtins.map (name: {
        name = stripMdExt name;
        value = claudeDirectory + "/commands/${name}";
      })
      (builtins.attrNames (builtins.readDir "${claudeDirectory}/commands")));
    skills = builtins.listToAttrs (builtins.map (name: {
        inherit name;
        value = claudeDirectory + "/skills/${name}/SKILL.md";
      })
      (builtins.attrNames (builtins.readDir "${claudeDirectory}/skills")));
  };
}
