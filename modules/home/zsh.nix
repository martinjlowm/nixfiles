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
        rustNightlyShell = ''nix shell "github:oxalica/rust-overlay#rust-nightly_$1"'';
        ls = "ls -Gal";
        sl = "ls";
        gs = "git status";
        extract-mp3 = "${pkgs.yt-dlp}/bin/yt-dlp --extract-audio --audio-format mp3 --audio-quality 0";
        keyfinder = "${pkgs.keyfinder-cli}/bin/keyfinder-cli";
        localhost = ''sed -E "s#(https://)([^/]+)#\\1localhost:3000#"'';
        wget = "curl -O --retry 999 --retry-max-time 0 -C -";
        just = "$HOME/.cargo/bin/just";
      }
      // lib.optionalAttrs isDarwin {
        # `rebuild` is a system package, not an alias: `sudo rebuild` resolves
        # against root's PATH. See scripts/rebuild.sh.
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
      ZENDESK_SUBDOMAIN = "factbird";
      ZENDESK_EMAIL = "mj@factbird.com";
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

      # aws-sso hands out nothing once its SSO token has expired: `console` and
      # `eval` print `FATAL Must run aws-sso login` and stop, and `list` serves
      # a stale cache or none at all. Logging in first turns that dead end into
      # a browser prompt. It costs one keyring read while the token is still
      # good, and `-L error` drops the "You are already logged in" line without
      # hiding the device code, which goes to stderr rather than the log.
      _aws_sso_login () {
        ${pkgs.aws-sso-cli}/bin/aws-sso login -L error
      }

      # One row per account/role pair, as `<account> (AccountId) » RoleName`
      # followed by a tab and the ARN. aws-sso writes no CSV header, but it
      # does end the CSV with a bare newline, so `NF >= 5` is what separates a
      # role from that last empty line. AccountName is whatever
      # ~/.config/aws-sso/config.yaml names the account and is empty until
      # someone writes it down, so the account column falls back to the alias
      # the SSO instance reports.
      #
      # Production accounts head the list: awk stamps each row with a rank that
      # `sort` orders on and `cut` then drops, so ties fall back to the string
      # fzf shows. `aws-sso list --sort` can do neither, since it orders one
      # printed field and knows nothing of the account column assembled here.
      _aws_sso_rows () {
        ${pkgs.aws-sso-cli}/bin/aws-sso list --csv AccountName AccountAlias AccountIdPad RoleName Arn 2>/dev/null \
          | ${pkgs.gawk}/bin/awk -F, 'NF >= 5 {
              account = ($1 == "" ? $2 : $1)
              rank = (tolower(account) ~ /production/) ? 0 : 1
              printf "%d\t%s (%s) » %s\t%s\n", rank, account, $3, $4, $5
            }' \
          | sort \
          | cut -f2-
      }

      # Pick one account/role pair and print its ARN. fzf shows and matches
      # field 1 only; field 2 carries the ARN through to the caller. A role
      # that appears or disappears without the token expiring needs an explicit
      # `aws-sso cache`.
      _aws_sso_pick () {
        # Factbird's palette: purple 500 frames the list, magenta 600 marks the
        # prompt and the cursor, blue 500 highlights what the query matched,
        # and grey carries the counters. bg:-1 leaves the terminal's own
        # background alone.
        local colors='fg:#CCCCCC,fg+:#FFFFFF,bg:-1,bg+:#333333,hl:#6DD1F1,hl+:#8AE3FF,border:#6C45EE,prompt:#FF00CC,pointer:#FF00CC,marker:#4CAF50,info:#919191,spinner:#FFC01D,header:#919191'
        _aws_sso_rows \
          | ${pkgs.fzf}/bin/fzf --delimiter=$'\t' --with-nth=1 --nth=1 \
              --prompt="$1 » " --query="''${2:-}" --select-1 --exit-0 \
              --height=40% --reverse --no-multi \
              --border=thinblock --color="$colors" \
          | cut -f2
      }

      a () {
        local arn
        _aws_sso_login || return 1
        arn=$(_aws_sso_pick 'Assume' "''${1:-}")
        [[ -n "$arn" ]] || return 1
        eval "$(${pkgs.aws-sso-cli}/bin/aws-sso eval --arn "$arn")"
      }

      c () {
        local arn
        _aws_sso_login || return 1
        arn=$(_aws_sso_pick 'Console' "''${1:-}")
        [[ -n "$arn" ]] || return 1
        ${pkgs.aws-sso-cli}/bin/aws-sso console --arn "$arn"
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

    # Lazily build a codegraph index when cd-ing into a worktree of a repo
    # that uses codegraph — one index per worktree, never a shared one at
    # the root. Opt-in per repo: triggers only when a sibling master/main
    # worktree (or the base checkout for nested layouts) is already
    # initialized; bootstrap a repo once with `codegraph init` in master.
    # scripts/worktree.sh runs the same init at worktree creation; this
    # hook covers pre-existing worktrees that never got an index.
    initContent = ''
      _codegraph_auto_init() {
        setopt LOCAL_OPTIONS NO_BG_NICE
        command -v codegraph >/dev/null 2>&1 || return 0
        local toplevel base
        toplevel=$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || return 0
        [[ -n $toplevel && ! -d $toplevel/.codegraph ]] || return 0
        base=''${toplevel:h}
        [[ -d $base/master/.codegraph || -d $base/main/.codegraph || -d $base/.codegraph ]] || return 0
        echo "[codegraph] indexing ''${toplevel:t} in background (log: /tmp/codegraph-init-''${toplevel:t}.log)"
        (codegraph init "$toplevel" && codegraph index "$toplevel") >"/tmp/codegraph-init-''${toplevel:t}.log" 2>&1 &!
      }
      autoload -U add-zsh-hook
      add-zsh-hook chpwd _codegraph_auto_init
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
