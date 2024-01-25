{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, home-manager, nixpkgs }:
    let
      configuration = { pkgs, ... }: {
        environment.systemPackages =
          with pkgs; [
            nerdfonts
            starship
            gh
            nodejs_20
            bun
            yarn
            rnix-lsp
            shortcat
            # bruno # Awaiting new unstable
            # yabai # Window Manager
            karabiner-elements # Key remapping
            rust-analyzer
            yt-dlp
            ffmpeg
            audacity
          ];

        services.nix-daemon.enable = true;

        nix.settings.experimental-features = "nix-command flakes";

        programs.zsh = {
          enable = true;
        };

        system.configurationRevision = self.rev or self.dirtyRev or null;

        system.stateVersion = 4;

        nixpkgs.hostPlatform = "x86_64-darwin";

        fonts.fontDir.enable = true;
        fonts.fonts = [ pkgs.nerdfonts ];
      };
      pkgs = import nixpkgs {
        system = "x86_64-darwin";
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
          allowUnsupportedSystem = true;
        };
      };
      userConfiguration = nix-darwin.lib.darwinSystem {
        inherit pkgs;
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit pkgs; };
            home-manager.users.martinjlowm = { pkgs, lib, config, ... }:
              let
                emacs = pkgs.emacs-macport.override {
                  withSQLite3 = true;
                };

                emacs-with-packages = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs: with epkgs; [
                  pkgs.mu
                  vterm
                  multi-vterm
                  pdf-tools
                  treesit-grammars.with-all-grammars
                ]);
              in
              {
                home.homeDirectory = nixpkgs.lib.mkForce "/Users/martinjlowm";
                home.stateVersion = "22.05";

                programs.starship = {
                  enable = true;
                };

                programs.emacs = {
                  enable = true;
                  package = emacs-with-packages;
                };

                programs.zsh = {
                  enable = true;
                  enableCompletion = true;
                  shellAliases = {
                    ls = "ls -Gal";
                    sl = "ls";
                    emacs = "${pkgs.emacs-macport}/Applications/Emacs.app/Contents/MacOS/Emacs";
                    extract-mp3 = "${pkgs.yt-dlp}/bin/yt-dlp --extract-audio --audio-format mp3 --audio-quality 0";
                    keyfinder = "${pkgs.keyfinder-cli}/bin/keyfinder-cli";
                  };
                  envExtra = ''
                    export ZSH_TMUX_AUTOSTART=true

                    bpm_key() {
                      FILE=$1
                      BPM_LIMIT=''${2:-180}
                      if [ ! -f "$FILE" ]; then
                        echo "File not found"
                        return;
                      fi
                      BPM=$(${pkgs.ffmpeg}/bin/ffmpeg -vn -i "$1" -ar 44100 -ac 1 -f f32le pipe:1 2>/dev/null | ${pkgs.bpm-tools}/bin/bpm -x $BPM_LIMIT -f "%03.0f")
                      KEY=$(${pkgs.keyfinder-cli}/bin/keyfinder-cli $FILE)
                      echo "''${BPM}_''${KEY}"
                    }

                    c () {
                      (assume -c -r eu-west-1 "$1")
                    }

                    a () {
                      assume -r eu-west-1 "$1"
                    }
                  '';
                  oh-my-zsh = {
                    enable = true;
                    plugins = [
                      "aws"
                      "common-aliases"
                      "direnv"
                      "tmux"
                      "isodate"
                      "macos"
                      "ripgrep"
                      "starship"
                      "thefuck"
                      "transfer"
                    ];
                  };
                };

                programs.ripgrep = {
                  enable = true;
                };

                programs.awscli = {
                  enable = true;
                };

                programs.git = {
                  enable = true;
                };

                programs.granted = {
                  enable = true;
                  enableZshIntegration = true;
                };

                programs.tmux = {
                  enable = true;
                  keyMode = "emacs";
                  mouse = true;
                  newSession = true;
                  shortcut = "z";
                  plugins = [
                    {
                      plugin = pkgs.tmuxPlugins.onedark-theme;
                      extraConfig = "set -g @plugin 'odedlaz/tmux-onedark-theme'";
                    }
                    {
                      plugin = pkgs.tmuxPlugins.yank;
                      extraConfig = "set -g @plugin 'tmux-plugins/tmux-yank'";
                    }

                  ];
                };

                programs.atuin = {
                  enable = true;
                  enableZshIntegration = true;
                };

                programs.gh = {
                  enable = true;
                };

                programs.dircolors = {
                  enable = true;
                  enableZshIntegration = true;
                };

                programs.kitty = {
                  enable = true;
                  theme = "One Dark";
                  environment = {
                    "LS_COLORS" = "1";
                  };
                  shellIntegration = {
                    enableZshIntegration = true;
                  };
                  font = {
                    package = pkgs.nerdfonts;
                    name = "Hack Nerd Font Mono Regular";
                    size = 14;
                  };
                };
                programs.mpv = {
                  enable = true;
                };

                programs.thefuck = {
                  enable = true;
                };

                programs.vscode = {
                  enable = true;
                  extensions = with pkgs.vscode-extensions; [
                    # ntbbloodbath.doom-one
                    tuttieee.emacs-mcx
                    tiehuis.zig
                    rust-lang.rust-analyzer
                    # ms-vsliveshare.vsliveshare
                    kahole.magit
                    graphql.vscode-graphql
                  ];
                };

              };
          }
        ];
      };
    in
    {
      darwinConfigurations."macbook-pro-home" = userConfiguration;
      darwinConfigurations."wololobook" = userConfiguration;

      darwinPackages = userConfiguration.pkgs;
    };
}
