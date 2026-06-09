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
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = "jq -re '.tool_input.command' | grep -q 'python3' && { echo 'ERROR: Python is not allowed. Use Node.js instead.' >&2; exit 2; } || true";
              }
            ];
          }
        ];
      };
      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        OTEL_METRICS_EXPORTER = "otlp";
        OTEL_LOGS_EXPORTER = "otlp";
        OTEL_EXPORTER_OTLP_PROTOCOL = "grpc";
        OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4317";
        OTEL_METRIC_EXPORT_INTERVAL = "10000";
        OTEL_LOGS_EXPORT_INTERVAL = "5000";
        OTEL_LOG_TOOL_DETAILS = "1";
        OTEL_LOG_USER_PROMPTS = "1";
        OTEL_METRICS_INCLUDE_SESSION_ID = "true";
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
      attribution = {
        commit = "";
        pr = "";
      };
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
