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
      overlays =
        [
          inputs.onepassword-secrets.overlays.default
          # Flake inputs the default overlay builds from.
          (_: _: {agent-skills-src = inputs.agent-skills;})
          overlays.default
        ]
        ++ extraOverlays;
    };

  # The arguments every home-manager module receives
  mkHomeSpecialArgs = {system}: let
    mkNextPkgs = nixpkgs: mkPkgs {inherit system nixpkgs;};
  in {
    inherit inputs;
    pkgs = mkPkgs {inherit system;};
    nextPkgs = mkNextPkgs inputs.nextNixpkgs;
    nextPkgsDevenv = mkNextPkgs inputs.nextNixpkgsDevenv;
    nextPkgsClaude = mkNextPkgs inputs.nextNixpkgsClaude;
  };

  # Create a Darwin (macOS) system configuration
  mkDarwinSystem = {
    system ? "aarch64-darwin",
    hostname,
    username,
    modules ? [],
    extraPkgs ? {},
  }: let
    homeSpecialArgs = mkHomeSpecialArgs {inherit system;};
    inherit (homeSpecialArgs) pkgs nextPkgs nextPkgsDevenv;
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
            home-manager.extraSpecialArgs = homeSpecialArgs;
          }
        ]
        ++ modules;
    };

  # Create a standalone home-manager configuration, which the user activates
  # without root. Its packages go to ~/.nix-profile rather than
  # /etc/profiles/per-user, which only the system activation can write.
  mkHomeConfiguration = {
    system ? "aarch64-darwin",
    username,
    modules ? [],
  }: let
    homeSpecialArgs = mkHomeSpecialArgs {inherit system;};
  in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (homeSpecialArgs) pkgs;
      extraSpecialArgs = homeSpecialArgs;
      modules = [{home.username = username;}] ++ modules;
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
  inherit mkPkgs mkDarwinSystem mkHomeConfiguration mkNixosSystem nixpkgsConfig;
}
