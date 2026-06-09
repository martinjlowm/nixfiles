# Overlays for customizing packages
{
  # Main overlay for package customizations
  default = final: prev: {
    vorbis-tools = prev.vorbis-tools.overrideAttrs (old: {
      postPatch = null;
    });
    localproxy = prev.localproxy.overrideAttrs (old: {
      version = "3.2.0";
      src = final.fetchFromGitHub {
        owner = "aws-samples";
        repo = "aws-iot-securetunneling-localproxy";
        rev = "v3.2.0";
        hash = "sha256-bIJLGJhSzBVqJaTWJj4Pmw/shA4Y0CzX4HhHtQZjfj0=";
      };
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace CMakeLists.txt --replace-fail \
                    "REQUIRED COMPONENTS system log log_setup thread program_options date_time filesystem chrono" \
                    "REQUIRED COMPONENTS log log_setup thread program_options date_time filesystem chrono"
        '';
    });
    # Semantic code intelligence MCP server for Claude Code. Built from
    # source instead of the upstream `npx @colbymchenry/codegraph` installer;
    # the MCP entry it would write is wired via codegraph-mcp-servers below,
    # and the permissions live in modules/home/claude-code.nix. Pure JS/wasm
    # deps — no native addons.
    codegraph = final.buildNpmPackage rec {
      pname = "codegraph";
      version = "0.9.9";
      src = final.fetchFromGitHub {
        owner = "colbymchenry";
        repo = "codegraph";
        rev = "v${version}";
        hash = "sha256-Oy0WpllYQDmKpVhf+xI3Y18s+0x2bzkN8DDgTOJf4B4=";
      };
      npmDepsHash = "sha256-PnD1POY39S/qaS4fOwJyYnRsCxbJ9pm49yVVAGlGt/E=";
      # Upstream bundles Node 24; Node 25 is hard-blocked (V8 wasm JIT bug).
      nodejs = final.nodejs_24;
      meta = {
        description = "Semantic code intelligence for coding agents";
        homepage = "https://github.com/colbymchenry/codegraph";
        license = final.lib.licenses.mit;
        mainProgram = "codegraph";
      };
    };
    # Token-optimizing CLI proxy for coding agents (rewrites Bash commands
    # like `git status` -> `rtk git status` via a Claude Code PreToolUse
    # hook). Built from source instead of the upstream `rtk init -g`
    # installer; the hook entry and CLAUDE.md awareness block it would write
    # are declared in modules/home/claude-code.nix.
    rtk = final.rustPlatform.buildRustPackage rec {
      pname = "rtk";
      version = "0.42.3";
      src = final.fetchFromGitHub {
        owner = "rtk-ai";
        repo = "rtk";
        rev = "v${version}";
        hash = "sha256-UWiu6y3Ci5F5OYQZIB0QuFmgv+tRUTouD9RZfX+PcsA=";
      };
      # Vendored via importCargoLock instead of cargoHash: fetchCargoVendor's
      # python-requests UA is blocked by the crates.io API WAF (403), so the
      # index is remapped to the static CDN, which serves the same download
      # paths. That remap makes importCargoLock emit a second source section
      # for the crates.io index, which cargo rejects as a duplicate of its
      # builtin `crates-io` source — scrub it from the generated config.
      cargoDeps = let
        vendor = final.rustPlatform.importCargoLock {
          lockFile = ../lockfiles/rtk-Cargo.lock;
          extraRegistries = {
            "https://github.com/rust-lang/crates.io-index" = "https://static.crates.io/crates";
          };
        };
      in
        # Must be named cargo-vendor-dir: the generated config references the
        # vendor directory by that literal (hash-stripped) name.
        final.runCommand "cargo-vendor-dir" {} ''
          cp -r ${vendor} $out
          chmod -R u+w $out/.cargo
          ${final.gnused}/bin/sed -i \
            '/^\[source\."https:\/\/github\.com\/rust-lang\/crates\.io-index"\]$/,+2d' \
            $out/.cargo/config.toml
        '';
      # Unit tests probe the environment (git on PATH, network-ish curl
      # fixtures) and fail in the build sandbox.
      doCheck = false;
      meta = {
        description = "CLI proxy that compresses command output to cut LLM token consumption";
        homepage = "https://github.com/rtk-ai/rtk";
        license = final.lib.licenses.asl20;
        mainProgram = "rtk";
      };
    };
    # Canonical codegraph MCP entry, merged into every claude entry point:
    # the base wrapper below and each mkClaudeFlavor in scripts/default.nix.
    # Claude Code only reads server definitions from mutable state files
    # (~/.claude.json, .mcp.json) — never settings.json — so the declarative
    # channel is the --mcp-config flag.
    codegraph-mcp-servers = {
      codegraph = {
        type = "stdio";
        command = final.lib.getExe final.codegraph;
        args = ["serve" "--mcp"];
      };
    };
    claude-code = let
      isDarwin = final.stdenv.isDarwin;

      safehouse = let
        src = final.fetchurl {
          url = "https://raw.githubusercontent.com/eugene1g/agent-safehouse/3b6261ae75a0ee3c8b93edf08e1cd64fa13e09fc/dist/safehouse.sh";
          hash = "sha256-3ChG6ASozqjyRw2vBoympAqDVTFUcBc4buX6ZPno45s=";
        };
      in
        final.stdenvNoCC.mkDerivation {
          pname = "agent-safehouse";
          version = "a7377924efadf5e3b9eac6924dcf979f1dec0f8e";
          inherit src;
          dontUnpack = true;
          installPhase = ''
            install -Dm755 $src $out/bin/safehouse
          '';
        };
      unwrapped = prev.claude-code;

      triple = final.stdenv.hostPlatform.config;
      suffix = builtins.replaceStrings ["-"] ["_"] triple;

      # --- macOS-specific ---
      nixRunProfile = final.writeText "nix-run-symlink.sb" ''
        ;; Allow reading /run symlink so /run/current-system/sw/bin resolves.
        ;; safehouse's --add-dirs-ro resolves symlinks via realpath, so /run
        ;; is never emitted as a literal in the sandbox profile.
        (allow file-read* (literal "/run"))
      '';

      opnix = final.opnix;
      opnixEnvConfig = final.writeText "claude-opnix-env.json" (builtins.toJSON {
        vars = [
          {
            name = "GH_TOKEN";
            reference = "op://Developer/Claude Code GitHub/Section_hkqdyxymn2ko5dudp7hdld6cre/token";
          }
        ];
      });

      denyGhConfig = final.writeText "deny-gh-config.sb" ''
        (deny file-read* file-write* (home-subpath "/.config/gh"))
      '';

      # --- Shared ---
      ghEmptyConfig = final.runCommand "gh-empty-config" {} "mkdir -p $out";

      codegraphMcpConfig = final.writeText "codegraph-mcp.json" (builtins.toJSON {
        mcpServers = final.codegraph-mcp-servers;
      });

      ghWrapped = final.writeShellScriptBin "gh" ''
        args=()
        for arg in "$@"; do
          case "$arg" in
            --admin) ;;
            *) args+=("$arg") ;;
          esac
        done
        exec ${final.gh}/bin/gh "''${args[@]}"
      '';

      envVars = [
        "PATH" "HOME" "USER" "TERM"
        "GH_TOKEN" "GH_CONFIG_DIR"
        "ZENDESK_SUBDOMAIN" "ZENDESK_EMAIL"
        "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN"
        "AWS_REGION" "AWS_DEFAULT_REGION"
        "NIX_CFLAGS_COMPILE" "NIX_CFLAGS_COMPILE_FOR_BUILD"
        "NIX_LDFLAGS" "NIX_LDFLAGS_FOR_BUILD"
        "CARGO_TARGET_DIR" "RUST_SRC_PATH"
        "NODE_OPTIONS" "PLAYWRIGHT_BROWSERS_PATH" "PUPPETEER_EXECUTABLE_PATH"
        "NIX_CC_WRAPPER_TARGET_HOST_${suffix}" "NIX_CC_WRAPPER_TARGET_BUILD_${suffix}"
        "SIGNOZ_API_KEY"
      ];

      envPassMacOS = builtins.concatStringsSep "," envVars;

      # bwrap: --setenv VAR "$VAR" for each set variable
      envPassLinux = builtins.concatStringsSep "\n" (map (v: ''
        if [[ -n "''${${v}:-}" ]]; then
          sandbox_args+=(--setenv "${v}" "''${${v}}")
        fi
      '') envVars);

      wrapper = final.writeShellScript "claude" ''
        ${if isDarwin then ''
        eval "$(${opnix}/bin/opnix env -config ${opnixEnvConfig} -token-file "''${OPNIX_ENV_TOKEN_FILE:-$HOME/.config/opnix/token}")"
        '' else ""}
        export GH_CONFIG_DIR="${ghEmptyConfig}"
        export PATH="${ghWrapped}/bin:$PATH"

        add_dirs="$PWD"
        if [[ -n "''${CARGO_TARGET_DIR:-}" ]]; then
          add_dirs="$add_dirs:$CARGO_TARGET_DIR"
        fi

        extra_ro_dirs=""
        extra_rw_dirs=""
        claude_args=()
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --add-dirs-ro=*)
              extra_ro_dirs="''${extra_ro_dirs:+$extra_ro_dirs:}''${1#--add-dirs-ro=}"
              shift
              ;;
            --add-dirs-ro)
              extra_ro_dirs="''${extra_ro_dirs:+$extra_ro_dirs:}$2"
              shift 2
              ;;
            --add-dirs=*)
              extra_rw_dirs="''${extra_rw_dirs:+$extra_rw_dirs:}''${1#--add-dirs=}"
              shift
              ;;
            --add-dirs)
              extra_rw_dirs="''${extra_rw_dirs:+$extra_rw_dirs:}$2"
              shift 2
              ;;
            *)
              claude_args+=("$1")
              shift
              ;;
          esac
        done

        # Enable codegraph for every session. Trailing placement is load-bearing:
        # --mcp-config is variadic, so ahead of the user args it swallows
        # positional prompts as config paths. Subcommands (claude mcp list,
        # claude doctor, ...) reject the flag outright, so skip those.
        mcp_args=(--mcp-config ${codegraphMcpConfig})
        case "''${claude_args[0]:-}" in
          agents|auth|auto-mode|config|doctor|install|mcp|migrate-installer|plugin|plugins|project|setup-token|ultrareview|update|upgrade)
            mcp_args=()
            ;;
        esac

        ${if isDarwin then ''
        ro_dirs="/nix:/private/etc:$HOME/.nix-defexpr"
        '' else ''
        ro_dirs="/nix:/etc:/run:$HOME/.nix-defexpr"
        ''}
        if [[ -n "$extra_ro_dirs" ]]; then
          ro_dirs="$ro_dirs:$extra_ro_dirs"
        fi

        rw_dirs="$add_dirs:$HOME/.cache:$HOME/.local/share:$HOME/.claude"
        if [[ -n "$extra_rw_dirs" ]]; then
          rw_dirs="$rw_dirs:$extra_rw_dirs"
        fi

        ${if isDarwin then ''
        exec ${safehouse}/bin/safehouse \
          --add-dirs-ro="$ro_dirs" \
          --append-profile=${nixRunProfile} \
          --append-profile=${denyGhConfig} \
          --enable agent-browser \
          --add-dirs="$rw_dirs" \
          --env-pass=${envPassMacOS} \
          -- ${unwrapped}/bin/claude --dangerously-skip-permissions "''${claude_args[@]}" "''${mcp_args[@]}"
        '' else ''
        sandbox_args=()

        # Essential system mounts
        sandbox_args+=(--dev /dev --proc /proc --tmpfs /tmp)

        # Read-only bind mounts
        IFS=':' read -ra _ro_paths <<< "$ro_dirs"
        for p in "''${_ro_paths[@]}"; do
          if [[ -n "$p" ]] && [[ -e "$p" ]]; then
            sandbox_args+=(--ro-bind "$p" "$p")
          fi
        done

        # Read-write bind mounts
        IFS=':' read -ra _rw_paths <<< "$rw_dirs"
        for p in "''${_rw_paths[@]}"; do
          if [[ -n "$p" ]]; then
            mkdir -p "$p"
            sandbox_args+=(--bind "$p" "$p")
          fi
        done

        # Pass through environment variables
        ${envPassLinux}

        # Namespace isolation with network access preserved
        sandbox_args+=(--unshare-all --share-net)

        exec ${final.bubblewrap}/bin/bwrap "''${sandbox_args[@]}" \
          -- ${unwrapped}/bin/claude --dangerously-skip-permissions "''${claude_args[@]}" "''${mcp_args[@]}"
        ''}
      '';
    in
      final.symlinkJoin {
        name = "claude-code-safehouse";
        paths = [unwrapped];
        inherit (unwrapped) meta;
        postBuild = ''
          rm $out/bin/claude
          ln -s ${wrapper} $out/bin/claude
        '';
      };
    whatsapp-for-mac = prev.whatsapp-for-mac.overrideAttrs (old: {
      version = "2.26.9.17";

      src = prev.fetchzip {
        extension = "zip";
        name = "WhatsApp.app";
        url = "https://web.whatsapp.com/desktop/mac_native/release/?version=2.26.9.17&extension=zip&configuration=Release&branch=master";
        hash = "sha256-bba22HBnIeio4M92mckiOa1IQpRUfx/I7OkfA4hO6rU=";
      };
    });
  };
}
