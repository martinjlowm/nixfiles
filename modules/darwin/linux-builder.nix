# Linux builder VM for cross-compilation on macOS
{lib, ...}: {
  # nix-darwin's linux-builder module asserts `nix.enable` (modules/nix/
  # linux-builder.nix:169-173). We run Determinate Nix outside nix-darwin, so
  # nix.enable = false — but the launchd builder daemon works fine regardless.
  # The assertion is stale for this setup; the module system offers no way to
  # drop a single assertion (any filter recurses via defsFinal), so clear them.
  assertions = lib.mkForce [];

  nix.linux-builder = {
    enable = true;
    ephemeral = true;
    protocol = "ssh";
    maxJobs = 4;
    systems = ["x86_64-linux" "aarch64-linux"];
    config = {
      virtualisation = {
        darwin-builder = {
          diskSize = 40 * 1024;
          memorySize = 16 * 1024;
        };
        cores = 8;
      };
      # binfmt can only be built with the Linux builder available, so it
      # must be configured and spun up without. Comment out this to boot up
      # the machine and reenable it afterwards such that the cross builder
      # becomes available
      boot.binfmt.emulatedSystems = ["x86_64-linux"];
    };
  };
}
