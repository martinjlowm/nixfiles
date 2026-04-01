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
    claude-code = let
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
      nixRunProfile = final.writeText "nix-run-symlink.sb" ''
        ;; Allow reading /run symlink so /run/current-system/sw/bin resolves.
        ;; safehouse's --add-dirs-ro resolves symlinks via realpath, so /run
        ;; is never emitted as a literal in the sandbox profile.
        (allow file-read* (literal "/run"))
      '';

      triple = final.stdenv.hostPlatform.config; # e.g. "aarch64-apple-darwin"
      suffix = builtins.replaceStrings ["-"] ["_"] triple; # "aarch64_apple_darwin"

      wrapper = final.writeShellScript "claude" ''
        add_dirs="$PWD"
        if [[ -n "$CARGO_TARGET_DIR" ]]; then
          add_dirs="$add_dirs:$CARGO_TARGET_DIR"
        fi

        extra_ro_dirs=""
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
            *)
              claude_args+=("$1")
              shift
              ;;
          esac
        done

        ro_dirs="/nix:/private/etc:$HOME/.nix-defexpr"
        if [[ -n "$extra_ro_dirs" ]]; then
          ro_dirs="$ro_dirs:$extra_ro_dirs"
        fi

        exec ${safehouse}/bin/safehouse \
          --add-dirs-ro="$ro_dirs" \
          --append-profile=${nixRunProfile} \
          --add-dirs="$add_dirs:$HOME/.cache/nix:$HOME/.local/share" \
          --env-pass=PATH,ZENDESK_SUBDOMAIN,ZENDESK_EMAIL,AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_SESSION_TOKEN,AWS_REGION,AWS_DEFAULT_REGION,NIX_CFLAGS_COMPILE,NIX_CFLAGS_COMPILE_FOR_BUILD,NIX_LDFLAGS,NIX_LDFLAGS_FOR_BUILD,CARGO_TARGET_DIR,RUST_SRC_PATH,NODE_OPTIONS,PLAYWRIGHT_BROWSERS_PATH,PUPPETEER_EXECUTABLE_PATH,NIX_CC_WRAPPER_TARGET_HOST_${suffix},NIX_CC_WRAPPER_TARGET_BUILD_${suffix} \
          -- ${unwrapped}/bin/claude --dangerously-skip-permissions "''${claude_args[@]}"
      '';
    in
      final.symlinkJoin {
        name = "claude-code-safehouse";
        paths = [unwrapped];
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
