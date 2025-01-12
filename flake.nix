{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # oldNixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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
            # (zed-editor.override {
            #   stdenv = pkgs.overrideSDK stdenv {
            #     darwinMinVersion = "10.15";
            #     darwinSdkVersion = "12.3";
            #   };
            # })
            bun
            yarn
            # bruno
            karabiner-elements # Key remapping
            rust-analyzer
            yt-dlp
            jdk
            # wine64
            nix-tree
            (ffmpeg.override {
              withWebp = true;
            })
            audacity
            gimp
            ast-grep
            cargo
            biome
            teams
            qemu
            git-lfs
            _1password-gui
            maccy
            darwin.apple_sdk.sdk
            nix-index
          ];

        services.nix-daemon.enable = true;
        services.yabai = {
          enable = true;
          config = {
            layout = "bsp";
          };
          extraConfig = ''
            yabai -m rule --add app="System Settings" manage=off

            yabai -m rule --add app="^Chrome$" space=^3
            yabai -m rule --add app="^FireFox$" space=^3
            yabai -m rule --add app="^Telegram$" space=4
            yabai -m rule --add app="^Music$" space=5
            yabai -m rule --add app="^Spotify$" space=5

          '';
        };

        # launchd.user.agents.shortcat = {
        #   serviceConfig.ProgramArguments = [ "${pkgs.shortcat}/Applications/Shortcat.app/Contents/MacOS/Shortcat" ];

        #   serviceConfig.KeepAlive = true;
        #   serviceConfig.RunAtLoad = true;
        # };

        nix.settings.experimental-features = "nix-command flakes";

        programs.zsh = {
          enable = true;
        };

        system.configurationRevision = self.rev or self.dirtyRev or null;

        system.stateVersion = 4;

        nixpkgs.hostPlatform = "x86_64-darwin";

        fonts.packages = [ pkgs.nerdfonts ];

        nix.gc.automatic = true;

        nix.linux-builder = {
          enable = true;
          ephemeral = true;
          maxJobs = 4;
          config = {
            virtualisation = {
              darwin-builder = {
                diskSize = 40 * 1024;
                memorySize = 8 * 1024;
              };
              cores = 8;
            };
          };
        };

        nix.settings.trusted-users = ["@admin"];
      };
      pkgs = import nixpkgs {
        system = "x86_64-darwin";
        config = {
          allowUnfree = true;
          allowBroken = true;
          allowUnfreePredicate = (_: true);
          allowUnsupportedSystem = true;
        };
        overlays = [(final: prev: {
          emacs-macport = prev.emacs-macport.overrideAttrs (o: {
            configureFlags = o.configureFlags ++ [
              "CFLAGS=-DMAC_OS_X_VERSION_MAX_ALLOWED=101201"
              "CFLAGS=-DMAC_OS_X_VERSION_MIN_REQUIRED=101201"
            ];
          });
          vorbis-tools = prev.vorbis-tools.overrideAttrs (old: rec {
            # Presumably because of https://bugs.llvm.org/show_bug.cgi?id=28361 for LLVM 16 on MacOS
            AM_CFLAGS = "-fuse-ld=${prev.lld_18}/bin/ld64.lld";
          });
        })];
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

                  programs.direnv = {
                    enable = true;
                    enableZshIntegration = true;
                    nix-direnv.enable = true;
                    config = {
                      global = {
                        hide_env_diff = true;
                      };
                    };
                  };

                  programs.zsh = {
                    enable = true;
                    enableCompletion = true;
                    shellAliases = {
                      ls = "ls -Gal";
                      sl = "ls";
                      rebuild = "darwin-rebuild switch --flake ~/.config/nix-darwin -L";
                      emacs = "${pkgs.emacs-macport}/Applications/Emacs.app/Contents/MacOS/Emacs";
                      extract-mp3 = "${pkgs.yt-dlp}/bin/yt-dlp --extract-audio --audio-format mp3 --audio-quality 0";
                      keyfinder = "${pkgs.keyfinder-cli}/bin/keyfinder-cli";
                      localhost = ''sed -E "s#(https://)([^/]+)#\\1localhost:3000#"'';
                      wget = "curl -O --retry 999 --retry-max-time 0 -C -";
                    };
                    envExtra = ''
                      export ZSH_TMUX_AUTOSTART=true
                      export PATH=$PATH:$HOME/projects/tools/cli/bin
                      export PATH=$PATH:$HOME/projects/bbctl/target/release
                      export DIRENV_WARN_TIMEOUT=0

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

                      killPort () {
                        kill $(lsof -i:$1 | awk '{ print $2 }' | tail -n +2 | xargs)
                      }

                      developmentStats () {
                         # List of commits
                         git log -n 100 --oneline --pretty=format:"%<(30)%an%<(20)%ad%x09%s"

                         # Developer activity
                         git log -n 100 --oneline --pretty=format:"%<(30)%an%<(20)%ad%x09%s" | sort | awk '{ print $1 }' | uniq -c

                         # Task distribution
                         git log -n 100 --oneline --pretty=format:"%an,%ad,%s" | awk -F',' '{ print $3 }' | sort | awk -F'(' '{ print $1 }' | uniq -c
                      }

                      get_accounts_recursive() {
                        accounts=$(aws organizations list-accounts-for-parent --parent-id "$1" | jq -r '.Accounts[] | .Id')

                        for ou in $(aws organizations list-organizational-units-for-parent --parent-id "$1" --output text --query 'OrganizationalUnits[][Id]'); do
                          accounts="$accounts $(get_accounts_recursive "$ou")"
                        done

                        echo "$accounts" | xargs
                      }

                      BLACKBIRD_APPLICATIONS_OU=ou-h5j2-v74x4pj1
                      DEVELOPER_ACCOUNTS_OU=ou-h5j2-y3cktc2g

                      clouds () {
                        CURRENT_ACCOUNT=$(aws sts get-caller-identity | jq -r .Account)
                        if [ "$CURRENT_ACCOUNT" != "274906834921" ]; then
                          return;
                        fi

                        echo $(get_accounts_recursive $BLACKBIRD_APPLICATIONS_OU) $(get_accounts_recursive $DEVELOPER_ACCOUNTS_OU)
                      }

                      assume_role () {
                        CREDENTIALS=`aws sts assume-role --role-arn arn:aws:iam::''${1}:role/AWSControlTowerExecution --role-session-name "$USER" --duration-seconds 3600 --output=json`

                        export AWS_ACCESS_KEY_ID=`echo ''${CREDENTIALS} | jq -r '.Credentials.AccessKeyId'`
                        export AWS_SECRET_ACCESS_KEY=`echo ''${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey'`
                        export AWS_SESSION_TOKEN=`echo ''${CREDENTIALS} | jq -r '.Credentials.SessionToken'`
                        export AWS_EXPIRATION=`echo ''${CREDENTIALS} | jq -r '.Credentials.Expiration'`

                        echo "» Changed context to $cloud ($AWS_ACCESS_KEY_ID)."
                      }

                      replace () {
                        ${pkgs.ripgrep}/bin/rg $1 --files-with-matches | xargs sed -i "s/$1/$2/g"
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
                    extraConfig = ''
                      set-option -g default-shell /bin/zsh
                      bind -n -T copy-mode M-w send-keys -X copy-pipe-and-cancel "pbcopy"
                      bind -n M-v copy-mode -u
                      bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "~/.tmux.conf reloaded"
                    '';
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
                    themeFile = "OneDark";
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
                    settings = {
                      macos_option_as_alt = true;
                      cursor_shape = "block";
                    };
                  };

                  # Disabled due to Swift failing to build -> awaiting
                  # progression on
                  # https://github.com/NixOS/nixpkgs/issues/344920#issuecomment-2379762180
                  # programs.mpv = {
                  #   enable = true;
                  # };

                  programs.thefuck = {
                    enable = true;
                  };

                  programs.vscode = {
                    enable = true;
                    extensions = with pkgs.vscode-extensions; [
                      tuttieee.emacs-mcx
                      tiehuis.zig
                      rust-lang.rust-analyzer
                      kahole.magit
                      graphql.vscode-graphql
                    ];
                  };


                };

          }
          ./1password.nix
          {
            programs._1password.enable = true;
            programs._1password-gui.enable = true;
          }
        ];
      };
    in
      {
        darwinConfigurations."Martins-MacBook-Pro" = userConfiguration;
        darwinConfigurations."wololobook" = userConfiguration;

        darwinPackages = userConfiguration.pkgs;
      };
}
