# Lima VM that builds aarch64-linux natively and x86_64-linux through Rosetta 2
{
  config,
  inputs,
  lib,
  ...
}: {
  imports = [inputs.nix-rosetta-builder.darwinModules.default];

  nix-rosetta-builder = {
    onDemand = true;
    cores = 8;
    memory = "16GiB";
    diskSize = "40GiB";
  };

  # Determinate Nix owns nix.conf, so nix.enable is false and nix-darwin writes
  # nothing from nix.buildMachines. Render the machines file here instead; the
  # Determinate nix.conf reads it through the default `builders = @/etc/nix/machines`.
  environment.etc."nix/machines" = {
    text = lib.concatMapStrings (m:
      lib.concatStringsSep " " [
        "${m.protocol}://${m.hostName}"
        (lib.concatStringsSep "," m.systems)
        "-"
        (toString m.maxJobs)
        (toString m.speedFactor)
        (lib.concatStringsSep "," m.supportedFeatures)
        "-"
        "-"
      ]
      + "\n")
    config.nix.buildMachines;
    # nix-darwin overwrites an unmanaged /etc file only when its hash is listed.
    knownSha256Hashes = ["62c4ca31a3b1a4122c1d67e7feb5daf5ff644aad3cfbb7e0151677a5806d9e24"];
  };
}
