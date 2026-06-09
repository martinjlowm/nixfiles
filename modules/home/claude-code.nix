# Claude Code configuration
{
  nextPkgsClaude,
  pkgs,
  lib,
  ...
}: let
  claudeDirectory = ../../config/claude;
  stripMdExt = name: lib.removeSuffix ".md" name;
in {
  # CLI on PATH for manual use (codegraph status/query/impact ...). The MCP
  # server itself is injected via pkgs.codegraph-mcp-servers: the claude-code
  # overlay wrapper and every mkClaudeFlavor pass it with --mcp-config.
  # NOT declared via programs.claude-code.mcpServers: that option never
  # writes config files — it wraps the binary with the variadic --mcp-config
  # flag ahead of "$@", which swallows positional args (`claude "prompt"`
  # and `claude mcp list` both break with "MCP config file not found").
  home.packages = [pkgs.codegraph];

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
      model = "fable";
      # Auto-allow list codegraph's installer would add. Redundant while the
      # sandbox wrapper passes --dangerously-skip-permissions, but kept for
      # parity in case that ever changes.
      permissions.allow = [
        "mcp__codegraph__codegraph_explore"
        "mcp__codegraph__codegraph_search"
        "mcp__codegraph__codegraph_node"
        "mcp__codegraph__codegraph_callers"
        "mcp__codegraph__codegraph_callees"
        "mcp__codegraph__codegraph_impact"
        "mcp__codegraph__codegraph_files"
        "mcp__codegraph__codegraph_status"
      ];
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
