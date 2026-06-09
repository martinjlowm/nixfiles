{
  description = "NixOS and nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nextNixpkgsDevenv.url = "github:NixOS/nixpkgs/e99366c665bdd53b7b500ccdc5226675cfc51f45";
    nextNixpkgs.url = "github:NixOS/nixpkgs/d1c2cd5033acedf3f29affd8d44e288107e95238";
    nextNixpkgsClaude.url = "github:samestep/nixpkgs/5900fe6cf8eca7dc124309029a50c7f80e90b6c9";

    nix-darwin.url = "github:martinjlowm/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    onepassword-secrets.url = "github:brizzbuzz/opnix";
    onepassword-secrets.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    home-manager,
    nixpkgs,
    nextNixpkgsDevenv,
    nextNixpkgsClaude,
    nextNixpkgs,
    onepassword-secrets,
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

    # Script packages
    packages = let
      systems = ["aarch64-darwin" "x86_64-linux" "x86_64-darwin" "aarch64-linux"];
      scriptNames = ["dependabot" "fix" "git-bug-hotspots" "git-commit-velocity" "git-contributor-rankings" "git-firefighting" "git-most-changed" "git-recent-contributors" "github-issues" "github-project" "loop" "playwright-at" "pr-maintenance" "pr-review" "project" "rmtree" "tech-spec" "worktree"];
    in
      builtins.listToAttrs (map (system: {
          name = system;
          value = let
            pkgs = lib.mkPkgs {inherit system;};
            scripts = pkgs.callPackage ./scripts {};
          in
            nixpkgs.lib.getAttrs scriptNames scripts
            // {
              claude-code = pkgs.claude-code;
            };
        })
        systems);
  };
}
