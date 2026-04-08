{pkgs, ...}: let
  wezterm = pkgs.wezterm;

  claude-follow = pkgs.writeShellApplication {
    name = "claude-follow";
    runtimeInputs = [pkgs.jq];
    checkPhase = "";
    text = builtins.readFile ./claude-follow.sh;
  };

  claude-sleep = pkgs.writeShellApplication {
    name = "claude-sleep";
    runtimeInputs = [pkgs.coreutils];
    checkPhase = "";
    text = builtins.readFile ./claude-sleep.sh;
  };

  mkWeztermScript = name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [wezterm claude-follow claude-sleep];
      checkPhase = "";
      text = builtins.readFile ./${name}.sh;
    };

  mkClaudeFlavor = {
    name,
    purpose,
    mcpServers,
  }: let
    mcpConfig = pkgs.writeText "${name}-mcp.json" (builtins.toJSON {
      mcpServers = mcpServers;
    });
  in
    pkgs.writeShellApplication {
      inherit name;
      checkPhase = "";
      text = ''
        # Skip --session-id when resuming or continuing an existing session
        SESSION_ARGS=()
        if [[ " $* " != *" --resume "* ]] && [[ " $* " != *" --continue "* ]]; then
          SESSION_ID=$(uuidgen)
          SESSION_ARGS+=(--session-id "$SESSION_ID")
          echo "Session: $SESSION_ID"
        fi
        echo "🎯 ${name}: ${purpose}"
        exec claude "''${SESSION_ARGS[@]}" --mcp-config ${mcpConfig} "$@"
      '';
    };
in {
  inherit claude-follow;
  worktree = pkgs.writeShellApplication {
    name = "worktree";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.direnv
      pkgs.git
      pkgs.gnugrep
    ];
    checkPhase = "";
    text = builtins.readFile ./worktree.sh;
  };
  rmtree = pkgs.writeShellApplication {
    name = "rmtree";
    runtimeInputs = [
      pkgs.git
    ];
    checkPhase = "";
    text = builtins.readFile ./rmtree.sh;
  };
  loop = mkWeztermScript "loop";
  dependabot = mkWeztermScript "dependabot";
  project = mkWeztermScript "project";
  pr-maintenance = mkWeztermScript "pr-maintenance";
  github-issues = mkWeztermScript "github-issues";
  roadmap-sync = pkgs.writeShellApplication {
    name = "roadmap-sync";
    runtimeInputs = [wezterm pkgs.gh];
    checkPhase = "";
    text = builtins.readFile ./roadmap-sync.sh;
  };
  pr-ua = pkgs.writeShellApplication {
    name = "pr-ua";
    runtimeInputs = [
      pkgs.gh
      pkgs.jq
      pkgs.fzf
    ];
    checkPhase = "";
    text = builtins.readFile ./pr-ua.sh;
  };
  zendesk-ticket = pkgs.writeShellApplication {
    name = "zendesk-ticket";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    checkPhase = "";
    text = builtins.readFile ./zendesk-ticket.sh;
  };
  claude-pm = mkClaudeFlavor {
    name = "claude-pm";
    purpose = "Project Management — Notion and Figma integrations for planning and design workflows";
    mcpServers = {
      notion = {
        type = "http";
        url = "https://mcp.notion.com/mcp";
      };
      figma = {
        type = "http";
        url = "https://mcp.figma.com/mcp";
      };
    };
  };
  claude-ops = mkClaudeFlavor {
    name = "claude-ops";
    purpose = "Operations — Sentry and Datadog integrations for monitoring and incident response";
    mcpServers = {
      sentry = {
        type = "http";
        url = "https://mcp.sentry.dev/sse";
      };
      datadog-mcp = {
        type = "http";
        url = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
      };
    };
  };
  tech-spec = let
    mcpConfig = pkgs.writeText "tech-spec-mcp.json" (builtins.toJSON {
      mcpServers = {
        notion = {
          type = "http";
          url = "https://mcp.notion.com/mcp";
        };
      };
    });
    templatePath = ../config/claude/templates/tech-spec.md;
  in
    pkgs.writeShellApplication {
      name = "tech-spec";
      runtimeInputs = [pkgs.coreutils pkgs.git pkgs.gawk pkgs.gnugrep pkgs.gnused];
      checkPhase = "";
      text = ''
        export TECH_SPEC_TEMPLATE="${templatePath}"
        export TECH_SPEC_MCP_CONFIG="${mcpConfig}"
        ${builtins.readFile ./tech-spec.sh}
      '';
    };
  github-project = let
    estimationPath = ../config/claude/templates/ESTIMATION.md;
  in
    pkgs.writeShellApplication {
      name = "github-project";
      runtimeInputs = [pkgs.coreutils pkgs.git pkgs.gh pkgs.gawk pkgs.gnugrep pkgs.gnused];
      checkPhase = "";
      text = ''
        export ESTIMATION_TEMPLATE="${estimationPath}"
        ${builtins.readFile ./github-project.sh}
      '';
    };
}
