# Helper functions for building system configurations
{
  inputs,
  overlays,
}: let
  # Common nixpkgs configuration
  nixpkgsConfig = {
    allowUnfree = true;
    allowBroken = true;
    allowUnfreePredicate = _: true;
    allowUnsupportedSystem = true;
  };

  # Create a pkgs instance for a given system
  mkPkgs = {
    system,
    nixpkgs ? inputs.nixpkgs,
    extraOverlays ? [],
  }:
    import nixpkgs {
      inherit system;
      config = nixpkgsConfig;
      overlays = [overlays.default] ++ extraOverlays;
    };

  # Create a Darwin (macOS) system configuration
  mkDarwinSystem = {
    system ? "aarch64-darwin",
    hostname,
    username,
    modules ? [],
    extraPkgs ? {},
  }: let
    pkgs = mkPkgs {inherit system;};
    nextPkgs = mkPkgs {
      inherit system;
      nixpkgs = inputs.nextNixpkgs;
    };
    nextPkgsDevenv = mkPkgs {
      inherit system;
      nixpkgs = inputs.nextNixpkgsDevenv;
    };
  in
    inputs.nix-darwin.lib.darwinSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs nextPkgs nextPkgsDevenv hostname username;
      };
      modules =
        [
          inputs.home-manager.darwinModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit pkgs nextPkgs nextPkgsDevenv inputs;};
          }
        ]
        ++ modules;
    };

  # Create a NixOS (Linux) system configuration
  mkNixosSystem = {
    system ? "x86_64-linux",
    hostname,
    username,
    modules ? [],
    extraPkgs ? {},
  }: let
    pkgs = mkPkgs {inherit system;};
    nextPkgs = mkPkgs {
      inherit system;
      nixpkgs = inputs.nextNixpkgs;
    };
  in
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs system;
      specialArgs = {
        inherit inputs nextPkgs hostname username;
      };
      modules =
        [
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit pkgs nextPkgs inputs;};
          }
        ]
        ++ modules;
    };
in {
  inherit mkPkgs mkDarwinSystem mkNixosSystem nixpkgsConfig;
}
