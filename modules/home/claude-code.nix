# Git configuration
{nextPkgs, ...}: let
  claudeDirectory = ../../config/claude;
in {
  programs.claude-code = {
    enable = true;
    package = nextPkgs.claude-code;
    agents = builtins.listToAttrs (builtins.map (name: {
        inherit name;
        value = claudeDirectory + "/agents/${name}";
      })
      (builtins.attrNames (builtins.readDir "${claudeDirectory}/agents")));
    commands = builtins.listToAttrs (builtins.map (name: {
        inherit name;
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
