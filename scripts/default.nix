{pkgs, signozPort ? 8080, ...}: let
  wezterm = pkgs.wezterm;

  chrome-devtools-mcp = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "chrome-devtools-mcp";
    version = "0.21.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${version}.tgz";
      hash = "sha512-d+iqrRmcwpRFV3Q4DRCF2LCoq+WCRU3GhISKQ9v8g+1C2Uh8upj3urkjxNO4QIjhBMIYei/VQ1OQLFceby80Og==";
    };
    nativeBuildInputs = [pkgs.makeWrapper];
    unpackPhase = ''
      mkdir -p $out/lib/chrome-devtools-mcp
      tar xzf $src --strip-components=1 -C $out/lib/chrome-devtools-mcp
    '';
    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/chrome-devtools-mcp \
        --add-flags "$out/lib/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js"
    '';
  };

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

  mux-spawn = pkgs.writeShellApplication {
    name = "mux-spawn";
    runtimeInputs = [wezterm pkgs.tmux pkgs.coreutils];
    checkPhase = "";
    text = builtins.readFile ./mux-spawn.sh;
  };

  mkWeztermScript = name:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [wezterm mux-spawn claude-follow claude-sleep];
      checkPhase = "";
      text = builtins.readFile ./${name}.sh;
    };

  mkClaudeFlavor = {
    name,
    purpose,
    mcpServers,
    runtimeInputs ? [],
    preExec ? "",
  }: let
    mcpConfig = pkgs.writeText "${name}-mcp.json" (builtins.toJSON {
      # codegraph is enabled in every flavor; explicitly defined servers
      # win on a name clash.
      mcpServers = pkgs.codegraph-mcp-servers // mcpServers;
    });
  in
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      checkPhase = "";
      text = ''
        ${preExec}
        # Skip --session-id when resuming or continuing an existing session
        SESSION_ARGS=()
        if [[ " $* " != *" --resume "* ]] && [[ " $* " != *" --continue "* ]]; then
          SESSION_ID=$(uuidgen)
          SESSION_ARGS+=(--session-id "$SESSION_ID")
          echo "Session: $SESSION_ID"
        fi
        echo "🎯 ${name}: ${purpose}"
        # --mcp-config last: it is variadic and would swallow a positional
        # prompt in "$@" as config file paths if it came first.
        exec claude "''${SESSION_ARGS[@]}" "$@" --mcp-config ${mcpConfig}
      '';
    };

  signoz-mcp-server = pkgs.buildGoModule rec {
    pname = "signoz-mcp-server";
    version = "0.1.2";

    src = pkgs.fetchFromGitHub {
      owner = "SigNoz";
      repo = "signoz-mcp-server";
      tag = "v${version}";
      hash = "sha256-Epr8tub6BdbNnyPIbR3r37GXikREwz+8SFyUGcBdVtw=";
    };

    vendorHash = "sha256-MKm5he3bwwJUTCJ/L986lRGN0mYaWI5rOaeQyg/QeU8=";

    subPackages = ["cmd/server"];

    postInstall = ''
      mv $out/bin/server $out/bin/signoz-mcp-server
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
  fix = mkWeztermScript "fix";
  pr-review = mkWeztermScript "pr-review";
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
  pr-pr = pkgs.writeShellApplication {
    name = "pr-pr";
    runtimeInputs = [
      pkgs.git
      pkgs.gh
      pkgs.jq
      pkgs.fzf
    ];
    checkPhase = "";
    text = builtins.readFile ./pr-pr.sh;
  };
  pr-ready = pkgs.writeShellApplication {
    name = "pr-ready";
    runtimeInputs = [
      pkgs.gh
      pkgs.jq
      pkgs.fzf
      pkgs.gnugrep
    ];
    checkPhase = "";
    text = builtins.readFile ./pr-ready.sh;
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
  claude-dbg = mkClaudeFlavor {
    name = "claude-dbg";
    purpose = "Debugging — SignOZ observability integration for traces, logs, and metrics analysis";
    runtimeInputs = [pkgs.jq pkgs._1password-cli pkgs.nodejs];
    preExec = ''
      OP_ACCOUNT=$(op account list --format=json | jq -r '.[] | select(.email == "martinjlowm@gmail.com") | .user_uuid')
      if [[ -z "$OP_ACCOUNT" ]]; then
        echo "ERROR: Could not find 1Password account for martinjlowm@gmail.com" >&2
        exit 1
      fi

      export SIGNOZ_API_KEY
      SIGNOZ_API_KEY=$(op item get "SigNoz API Token" --account "$OP_ACCOUNT" --fields credential --reveal) || {
        echo "ERROR: Failed to retrieve SigNoz API token from 1Password" >&2
        exit 1
      }
    '';
    mcpServers = {
      signoz = {
        command = "${signoz-mcp-server}/bin/signoz-mcp-server";
        args = [];
        env = {
          SIGNOZ_URL = "http://localhost:${toString signozPort}";
          SIGNOZ_API_KEY = "\${SIGNOZ_API_KEY}";
          LOG_LEVEL = "info";
        };
      };
      chrome-devtools = {
        command = "${chrome-devtools-mcp}/bin/chrome-devtools-mcp";
        args = [
          "--browser-url=http://127.0.0.1:9222"
        ];
      };
    };
  };
  tech-spec = let
    mcpConfig = pkgs.writeText "tech-spec-mcp.json" (builtins.toJSON {
      mcpServers =
        pkgs.codegraph-mcp-servers
        // {
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
  git-most-changed = pkgs.writeShellApplication {
    name = "git-most-changed";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    checkPhase = "";
    text = builtins.readFile ./git-most-changed.sh;
  };
  git-contributor-rankings = pkgs.writeShellApplication {
    name = "git-contributor-rankings";
    runtimeInputs = [pkgs.git];
    checkPhase = "";
    text = builtins.readFile ./git-contributor-rankings.sh;
  };
  git-recent-contributors = pkgs.writeShellApplication {
    name = "git-recent-contributors";
    runtimeInputs = [pkgs.git];
    checkPhase = "";
    text = builtins.readFile ./git-recent-contributors.sh;
  };
  git-bug-hotspots = pkgs.writeShellApplication {
    name = "git-bug-hotspots";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    checkPhase = "";
    text = builtins.readFile ./git-bug-hotspots.sh;
  };
  git-commit-velocity = pkgs.writeShellApplication {
    name = "git-commit-velocity";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    checkPhase = "";
    text = builtins.readFile ./git-commit-velocity.sh;
  };
  git-firefighting = pkgs.writeShellApplication {
    name = "git-firefighting";
    runtimeInputs = [pkgs.git pkgs.gnugrep];
    checkPhase = "";
    text = builtins.readFile ./git-firefighting.sh;
  };
  playwright-at = pkgs.writeShellApplication {
    name = "playwright-at";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.nodejs];
    checkPhase = "";
    text = builtins.readFile ./playwright-at.sh;
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
