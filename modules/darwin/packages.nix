# Common Darwin packages
{
  pkgs,
  nextPkgs,
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
in {
  environment.systemPackages = with pkgs; [
    # Shell & CLI tools
    starship
    gh
    ripgrep
    nix-tree
    nix-index
    delta
    alejandra

    # Development - Node.js
    nodejs_24
    bun
    yarn
    typescript-language-server
    vscode-css-language-server
    vscode-eslint-language-server
    vscode-html-language-server
    vscode-json-language-server

    # Development - Rust
    rust-analyzer
    cargo
    biome

    # Development - Java
    jdk

    # Development - Other
    ast-grep
    git-lfs
    nextPkgs.devenv
    claude-code

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

    # Browsers & Apps
    brave
    discord
    firefox

    # LaTeX
    (texlive.combine {
      inherit (texlive) scheme-medium inter titlesec svg transparent;
    })
    texlab
  ];
}
