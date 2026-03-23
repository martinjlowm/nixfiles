# Claude Code configuration
{
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
        value = claudeDirectory + "/skills/${name}";
      })
      (builtins.attrNames (builtins.readDir "${claudeDirectory}/skills")));
    settings = {
      model = "opus";
      hooks = {
        PreToolUse = [
          {
            matcher = "AskUserQuestion";
            hooks = [
              {
                type = "command";
                command = "/Users/martinjlowm/.claude/hooks/block-ask-user-question.py";
              }
            ];
          }
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "/Users/martinjlowm/.claude/hooks/block-dangerous-git.py";
              }
              {
                type = "command";
                command = "jq -re '.tool_input.command' | grep -q 'python3' && { echo 'ERROR: Python is not allowed. Use Node.js instead.' >&2; exit 2; } || true";
              }
            ];
          }
        ];
      };
      enabledPlugins = {
        "ralph-loop@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "typescript-lsp@claude-plugins-official" = true;
        "aws-cdk@aws-skills" = true;
        "aws-cost-ops@aws-skills" = true;
        "document-skills@anthropic-agent-skills" = true;
      };
      skipDangerousModePermissionPrompt = true;
      extraKnownMarketplaces = {
        impeccable = {
          source = {
            source = "github";
            repo = "pbakaus/impeccable";
          };
        };
      };
    };
  };
}
