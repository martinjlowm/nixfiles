# Linux builder VM for cross-compilation on macOS
_: {
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
