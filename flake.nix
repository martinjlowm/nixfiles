{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nextNixpkgs.url = "github:NixOS/nixpkgs/8eaee110344796db060382e15d3af0a9fc396e0e";

    nix-darwin.url = "github:martinjlowm/nix-darwin/5c2bb92a99a6bb1957876ff5bb8be48423a9ac72";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, home-manager, nixpkgs, nextNixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowBroken = true;
          allowUnfreePredicate = (_: true);
          allowUnsupportedSystem = true;
        };
        overlays = [(final: prev: {
          # emacs-macport = prev.emacs-macport.overrideAttrs (o: {
          #   configureFlags = o.configureFlags ++ [
          #     "CFLAGS=-DMAC_OS_X_VERSION_MAX_ALLOWED=101201"
          #     "CFLAGS=-DMAC_OS_X_VERSION_MIN_REQUIRED=101201"
          #   ];
          # });
          vorbis-tools = prev.vorbis-tools.overrideAttrs (old: rec {
            postPatch = null;
          });
        })];
      };
      nextPkgs = import nextNixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowBroken = true;
          allowUnfreePredicate = (_: true);
          allowUnsupportedSystem = true;
        };
      };
      configuration = { pkgs, ... }:
        let
          pnpWrap = { name, bin }:
            pkgs.writers.writeBashBin name ''
              export NODE_OPTIONS="";
              ${pkgs.nodePackages_latest.yarn}/bin/yarn node ${bin} "$@"
            '';
          typescript-language-server = pnpWrap { name = "typescript-language-server"; bin = "${pkgs.typescript-language-server}/lib/node_modules/typescript-language-server/lib/cli.mjs"; };
          vscode-css-language-server = pnpWrap { name = "vscode-css-language-server"; bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-css-language-server"; };
          vscode-eslint-language-server = pnpWrap { name = "vscode-eslint-language-server"; bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-eslint-language-server"; };
          vscode-html-language-server = pnpWrap { name = "vscode-html-language-server"; bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-html-language-server"; };
          vscode-json-language-server = pnpWrap { name = "vscode-json-language-server"; bin = "${pkgs.vscode-langservers-extracted}/lib/node_modules/vscode-langservers-extracted/bin/vscode-json-language-server"; };
        in {
        environment.systemPackages =
          with pkgs; [
            starship
            gh
            nodejs_24
            # (zed-editor.override {
            #   stdenv = pkgs.overrideSDK stdenv {
            #     darwinMinVersion = "10.15";
            #     darwinSdkVersion = "12.3";
            #   };
            # })
            bun
            yarn
            ripgrep
            opentelemetry-collector
            # bruno
            karabiner-elements # Key remapping
            rust-analyzer
            yt-dlp
            jdk
            # wine64
            nix-tree
            heroku
            (ffmpeg.override {
              withWebp = true;
            })
            audacity
            gimp
            ast-grep
            cargo
            biome
            qemu
            git-lfs
            #nextPkgs._1password-gui
            maccy
            nix-index
            typescript-language-server
            vscode-css-language-server
            vscode-eslint-language-server
            vscode-html-language-server
            vscode-json-language-server
            nextPkgs.devenv
            claude-code
            influxdb2-cli
            brave
            discord
            firefox
            delta
            # nextPkgs.rustdesk-flutter
          ];

        services.yabai = {
          enable = true;
          package = (nextPkgs.yabai.overrideAttrs {
            src = pkgs.fetchzip {
              url = "https://github.com/koekeishiya/yabai/archive/refs/heads/ff42ceadc92dfc50df63b73e3e1384b8b4059864.zip";
              hash = "sha256-cDONHrNPBTzEkVqxN1cHDqVumfyfcHrTYGZxn4s/mEA=";
            };
            doInstallCheck = false;
          });
          config = {
            layout = "bsp";
            top_padding = 8;
            bottom_padding = 8;
            left_padding = 8;
            right_padding = 8;
            window_gap = 8;
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
        services.jankyborders = {
          enable = true;
          active_color = "0xFFFF00CC";
          inactive_color = "";
          width = 6.0;
        };
        networking.hostName = "wololobook";

        system.primaryUser = "martinjlowm";

        # launchd.user.agents.shortcat = {
        #   serviceConfig.ProgramArguments = [ "${pkgs.shortcat}/Applications/Shortcat.app/Contents/MacOS/Shortcat" ];

        #   serviceConfig.KeepAlive = true;
        #   serviceConfig.RunAtLoad = true;
        # };

        programs.zsh = {
          enable = true;
        };

        system.configurationRevision = self.rev or self.dirtyRev or null;

        system.stateVersion = 4;

        nixpkgs.hostPlatform = "x86_64-darwin";

        fonts.packages = [  ] ++ builtins.filter pkgs.lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

        nix.enable = false;

        nix.linux-builder = {
          enable = true;
          ephemeral = true;
          maxJobs = 4;
          systems = ["x86_64-linux" "aarch64-linux"];
          config = {
            virtualisation = {
              darwin-builder = {
                diskSize = 40 * 1024;
                memorySize = 8 * 1024;
              };
              cores = 8;
            };
            boot.binfmt.emulatedSystems = ["x86_64-linux"];
          };
        };

        nix.settings.trusted-users = ["@admin"];
      };

      userConfiguration = nix-darwin.lib.darwinSystem {
        inherit pkgs;
        specialArgs = {
          inherit nextPkgs;
        };
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit pkgs nextPkgs; };
            home-manager.users.martinjlowm = { pkgs, nextPkgs, lib, config, ... }:
              let
                emacs = pkgs.emacs-macport;

                allGrammars = (pkgs.emacsPackagesFor emacs).treesit-grammars.with-all-grammars;
                emacs-with-packages = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs: with epkgs; [
                  pkgs.mu
                  vterm
                  multi-vterm
                  pdf-tools
                  allGrammars
                  # (treesit-grammars.with-grammars  (p: [ p.tree-sitter-nix ]))
                  claude-shell
                ]);
              in
                {
                  home.homeDirectory = nixpkgs.lib.mkForce "/Users/martinjlowm";
                  home.stateVersion = "22.05";

                  home.file = {
                    ".config/emacs/.local/cache/tree-sitter".source =
                      "${allGrammars}/lib";
                  };

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
                      worktree = "source worktree";
                    };
                    sessionVariables = {
                      DEVENV_ENABLE_HOOKS = "true";
                      NIXPKGS_ALLOW_UNFREE = 1;
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

                      _just_completion() {
                          if [[ -f "justfile" ]]; then
                            local options
                            options="$(just --summary)"
                            reply=(''${(s: :)options})  # turn into array and write to return variable
                          fi
                      }

                      compctl -K _just_completion just
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
                    userName = "Martin Jesper Low Madsen";
                    userEmail = "mj@factbird.com";
                    aliases = {
                      stashgrep = ''
                        !f() {
                          for i in `git stash list --format=\"%gd\"`; do
                            git stash show -p $i | grep -H --label=\"$i\" \"$@\";
                          done;
                        };
                        f
                      '';
                    };
                    extraConfig = {
                      core = {
                        ignorecase = false;
                      };
                      push = {
                        autoSetupRemote = true;
                      };
                      pull = {
                        rebase = false;
                      };
                    };
                  };
                  programs.git-worktree-switcher = {
                    enable = true;
                  };
                  programs.mergiraf = {
                    enable = true;
                  };

                  programs.granted = {
                    enable = true;
                    enableZshIntegration = true;
                    package = nextPkgs.granted;
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
                      package = pkgs.nerd-fonts.hack;
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
          #./1password.nix
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
