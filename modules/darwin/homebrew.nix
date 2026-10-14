# Homebrew, for apps that need their vendor's code signature
{
  inputs,
  username,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  # nix-homebrew installs brew itself under /opt/homebrew; nix-darwin's
  # homebrew module below only drives a brew that already exists.
  nix-homebrew = {
    enable = true;
    user = username;
  };

  # macOS 27 denies the nixpkgs builds of these browsers access to their own
  # profile directories, and shows no prompt to grant it. nixpkgs signs only
  # the executable, ad hoc, so macOS has no stable identity to grant access
  # to. The casks ship the vendors' Developer ID bundles, so a grant survives
  # updates.
  homebrew = {
    enable = true;
    casks = [
      "brave-browser"
      "firefox"
    ];
  };
}
