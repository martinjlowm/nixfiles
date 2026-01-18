# ZSH shell configuration (cross-platform)
{
  pkgs,
  lib,
  ...
}: let
  inherit (pkgs.stdenv) isDarwin;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    shellAliases =
      {
        ls = "ls -Gal";
        sl = "ls";
        extract-mp3 = "${pkgs.yt-dlp}/bin/yt-dlp --extract-audio --audio-format mp3 --audio-quality 0";
        keyfinder = "${pkgs.keyfinder-cli}/bin/keyfinder-cli";
        localhost = ''sed -E "s#(https://)([^/]+)#\\1localhost:3000#"'';
        wget = "curl -O --retry 999 --retry-max-time 0 -C -";
        worktree = "source worktree";
        just = "$HOME/.cargo/bin/just";
      }
      // lib.optionalAttrs isDarwin {
        rebuild = "darwin-rebuild switch --flake ~/.config/nix-darwin -L";
        emacs = "${pkgs.emacs-macport}/Applications/Emacs.app/Contents/MacOS/Emacs";
      }
      // lib.optionalAttrs (!isDarwin) {
        rebuild = "sudo nixos-rebuild switch --flake ~/.config/nixos -L";
      };

    sessionVariables = {
      DEVENV_ENABLE_HOOKS = "true";
      DEVENV_ENABLE_MCP_SENTRY = "true";
      DEVENV_ENABLE_MCP_NOTION = "true";
      DEVENV_ENABLE_MCP_SERENA = "true";
      DEVENV_ENABLE_MCP_AWS_DIAGRAM = "true";
      DOCKER_HOST = "unix:///tmp/podman/podman-machine-default-api.sock";
      NIXPKGS_ALLOW_UNFREE = 1;
    };

    envExtra = ''
      export ZSH_TMUX_AUTOSTART=true
      export PATH=$PATH:$HOME/projects/tools/cli/bin
      export PATH=$PATH:$HOME/projects/bbctl/target/release
      export DIRENV_WARN_TIMEOUT=0
      export ODX_DSN='https://f1dda818e4f7eaab6da0e99677b2d664@o4508761006604288.ingest.de.sentry.io/4510126832943184'

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
      plugins =
        [
          "aws"
          "common-aliases"
          "direnv"
          # "tmux"
          "isodate"
          "starship"
          "transfer"
        ]
        ++ lib.optionals isDarwin ["macos"];
    };
  };
}
