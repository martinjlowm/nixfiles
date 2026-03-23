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
    in
      final.symlinkJoin {
        name = "claude-code-safehouse";
        paths = [unwrapped];
        nativeBuildInputs = [final.makeWrapper];
        postBuild = ''
          rm $out/bin/claude
          makeWrapper ${safehouse}/bin/safehouse $out/bin/claude \
            --add-flags "--add-dirs-ro=/nix --add-dirs-ro=/private/etc -- ${unwrapped}/bin/claude --dangerously-skip-permissions"
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
