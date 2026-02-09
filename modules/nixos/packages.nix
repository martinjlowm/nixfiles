# Common NixOS packages
{
  pkgs,
  nextPkgs,
  nextPkgsClaude,
  ...
}: {
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

    # Development - Rust
    rust-analyzer
    cargo
    biome

    # Development - Other
    ast-grep
    git-lfs
    nextPkgs.devenv
    nextPkgsClaude.claude-code

    # Media
    yt-dlp
    ffmpeg
    audacity

    # Cloud & Infrastructure
    influxdb2-cli
    podman
    attic-client
  ];

  # Enable common services
  programs.zsh.enable = true;
}
