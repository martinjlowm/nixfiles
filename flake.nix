{
  description = "NixOS and nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nextNixpkgsDevenv.url = "github:NixOS/nixpkgs/e99366c665bdd53b7b500ccdc5226675cfc51f45";
    nextNixpkgs.url = "github:NixOS/nixpkgs/d1c2cd5033acedf3f29affd8d44e288107e95238";
    nextNixpkgsClaude.url = "github:NixOS/nixpkgs/f4a9cd4f7cfa0ada33acab7d17eb3a6af3f6ba3b";

    nix-darwin.url = "github:martinjlowm/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    home-manager,
    nixpkgs,
    nextNixpkgsDevenv,
    nextNixpkgsClaude,
    nextNixpkgs,
  }: let
    # Import overlays
    overlays = import ./overlays;

    # Import helper functions
    lib = import ./lib {inherit inputs overlays;};

    # ──────────────────────────────────────────────────────────────
    # Darwin (macOS) Configurations
    # ──────────────────────────────────────────────────────────────

    # wololobook - MacBook Pro (Apple Silicon)
    wololobook = lib.mkDarwinSystem {
      system = "aarch64-darwin";
      hostname = "wololobook";
      username = "martinjlowm";
      modules = [
        ./hosts/darwin/wololobook
        {
          system.configurationRevision = self.rev or self.dirtyRev or null;
        }
      ];
    };
    # ──────────────────────────────────────────────────────────────
    # NixOS (Linux) Configurations
    # ──────────────────────────────────────────────────────────────
    # Example NixOS configuration (uncomment and customize when needed)
    # example-nixos = lib.mkNixosSystem {
    #   system = "x86_64-linux";
    #   hostname = "example-nixos";
    #   username = "martinjlowm";
    #   modules = [
    #     ./hosts/nixos/example
    #   ];
    # };
  in {
    # Darwin configurations
    darwinConfigurations = {
      "wololobook" = wololobook;
      "Martins-MacBook-Pro" = wololobook; # Alias for the same machine
    };

    # NixOS configurations (add your Linux machines here)
    nixosConfigurations = {
      # "example-nixos" = example-nixos;
    };

    # Expose packages for convenience
    darwinPackages = wololobook.pkgs;
  };
}
