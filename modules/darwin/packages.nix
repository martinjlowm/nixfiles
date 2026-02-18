# Common Darwin packages
{
  pkgs,
  nextPkgs,
  nextPkgsDevenv,
  ...
}: let
  pnpWrap = {
    name,
    bin,
  }:
    pkgs.writers.writeBashBin name ''
      export NODE_OPTIONS="";
      ${pkgs.nodePackages_latest.yarn}/bin/yarn node ${bin} "$@"
    '';

  typescript-language-server = pnpWrap {
    name = "typescript-language-server";
    bin = "${pkgs.typescript-language-server}/lib/node_modules/typescript-language-server/lib/cli.mjs";
  };

  vscode-css-language-server = pnpWrap {
    name = "vscode-css-language-server";
    bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-css-language-server";
  };

  vscode-eslint-language-server = pnpWrap {
    name = "vscode-eslint-language-server";
    bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-eslint-language-server";
  };

  vscode-html-language-server = pnpWrap {
    name = "vscode-html-language-server";
    bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-html-language-server";
  };

  vscode-json-language-server = pnpWrap {
    name = "vscode-json-language-server";
    bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-json-language-server";
  };
  agent-browser = pkgs.buildNpmPackage rec {
    pname = "agent-browser";
    version = "0.5.0";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
      hash = "sha256-IdeLrmuExcdV4V3h3IGeB8Q8jliLHqrran5ewP+k56A=";
    };

    postPatch = ''
      cp ${../../lockfiles/agent-browser.json} package-lock.json
    '';

    npmDepsHash = "sha256-pJgcKu27WP79vEEzEtJD243jT0ItJ6ii/TKym6TLtp0=";

    dontNpmBuild = true;

    # The bin entry is a bash script, not a node script - replace the node wrapper
    postFixup = ''
      rm $out/bin/agent-browser
      ln -s $out/lib/node_modules/agent-browser/bin/agent-browser $out/bin/agent-browser
    '';
  };
  zeroshot = pkgs.buildNpmPackage rec {
    pname = "zeroshot";
    version = "5.4.0";

    src = pkgs.fetchFromGitHub {
      owner = "covibes";
      repo = "zeroshot";
      tag = "v${version}";
      hash = "sha256-Q4k2s3lqdaKbSI7FdhztQl9ARFIk2aAK95QPp6RcjD0=";
    };

    postPatch = ''
      cp ${../../lockfiles/zeroshot.json} package-lock.json
    '';

    npmDepsHash = "sha256-8z6vRWSZTftxTcWoG5AnyCqBnCdc7ond4TiSJxq4zVE=";

    dontNpmBuild = true;
    PUPPETEER_SKIP_DOWNLOAD = "true";
  };
in {
  environment.systemPackages = with pkgs;
    [
      # Shell & CLI tools
      starship
      gh
      ripgrep
      nix-tree
      nix-index
      delta
      alejandra

      magic-wormhole

      # Development - Node.js
      nodejs_24
      bun
      yarn
      typescript-language-server
      vscode-css-language-server
      vscode-eslint-language-server
      vscode-html-language-server
      vscode-json-language-server

      agent-browser
      zeroshot

      # Development - Rust
      rust-analyzer
      cargo
      biome

      # Development - Java
      jdk

      # Development - Other
      ast-grep
      git-lfs
      nextPkgsDevenv.devenv

      # Media
      yt-dlp
      (ffmpeg.override {withWebp = true;})
      audacity

      # macOS specific
      karabiner-elements
      maccy

      # Cloud & Infrastructure
      heroku
      opentelemetry-collector
      influxdb2-cli
      ssm-session-manager-plugin
      attic-client
      podman
      inkscape

      # Browsers & Apps
      brave
      discord
      firefox

      # LaTeX
      (texlive.combine {
        inherit (texlive) scheme-medium inter titlesec svg transparent;
      })
      texlab
    ]
    ++ (pkgs.callPackage ../../scripts {});
}
