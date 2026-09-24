# aws-sso-cli configuration and the shell wrappers that drive it
{
  pkgs,
  lib,
  ...
}: let
  # aws-sso runs this command itself rather than handing the URL to `open`, so
  # on macOS it needs the executable inside the bundle. The bundle directory
  # does not work.
  brave = "${pkgs.brave}/Applications/Brave Browser.app/Contents/MacOS/Brave Browser";

  # UrlExecCommand receives one argument, `%s`, so the profile a URL belongs to
  # has to come out of the URL itself. UrlAction below rewrites every console
  # URL into `ext+granted-containers:name=<profile>&url=<escaped>&color=<c>&icon=<i>`,
  # whose `name` is the ProfileFormat string. AuthUrlAction hands over a bare
  # https URL instead, and that login page, which no role owns, opens in
  # Brave's own profile.
  #
  # ProfileFormat emits neither `&` nor `=`, so splitting on `&` and cutting at
  # the first `=` recovers the profile whole. `url` arrives as Go's QueryEscape
  # output, where `+` is a space and every character outside `[A-Za-z0-9-_.~]`
  # is `%XX`, so the only backslash `printf %b` ever sees is the one this
  # substitutes for `%`.
  #
  # Chromium creates a profile directory the first time it is named, so a role
  # assumed for the first time gets a cookie jar of its own without anyone
  # setting one up, and two roles held at once never share one.
  openUrl = pkgs.writeShellScript "aws-sso-brave" ''
    uri=$1
    profile=Default
    target=$uri

    if [[ $uri == ext+granted-containers:* ]]; then
      IFS='&' read -r -a fields <<< "''${uri#ext+granted-containers:}"
      for field in "''${fields[@]}"; do
        case $field in
          name=*) profile=''${field#name=} ;;
          url=*) target=''${field#url=} ;;
        esac
      done
      target=''${target//+/ }
      target=$(printf '%b' "''${target//%/\\x}")
    fi

    exec "${brave}" --profile-directory="$profile" "$target"
  '';

  # Every Identity Center portal, in the order their roles reach the picker.
  # `name` is what `aws-sso -S` answers to and what keys that portal's own
  # token and role cache; `label` is what the picker prints. The two match
  # today, and a portal whose `-S` name reads badly in a list can part them.
  #
  # Neither portal is named `Default`, the name aws-sso falls back to on its
  # own, so DefaultSSO below is what a bare `aws-sso ...` follows to work.
  instances = [
    {
      name = "Factbird";
      label = "Factbird";
      startUrl = "https://blackbird.awsapps.com/start";
      region = "eu-west-1";
    }
    {
      name = "martinjlowm";
      label = "martinjlowm";
      startUrl = "https://martinjlowm.awsapps.com/start";
      region = "eu-west-1";
    }
  ];

  # AuthUrlAction sits per instance and runs the same command as UrlAction,
  # minus the rewrite that names a profile, so the login page opens in Brave's
  # own profile rather than one named for a role.
  ssoEntry = i:
    "    ${i.name}:\n"
    + "        SSORegion: ${i.region}\n"
    + "        StartUrl: ${i.startUrl}\n"
    + "        AuthUrlAction: exec\n";

  # `<instance name>:<picker label>` per portal, for the shell to split.
  instanceList = lib.concatMapStringsSep " " (i: "${i.name}:${i.label}") instances;

  # The file-level settings are pasted rather than generated from an attribute
  # set, because every YAML generator in nixpkgs sorts the keys and reindents
  # to two spaces, which would leave the file unrecognisable next to the one
  # aws-sso's wizard wrote. ssoEntry concatenates the SSOConfig block by hand
  # for the same reason. Three settings differ from the wizard's file:
  #
  #   AuthUrlAction   see ssoEntry above
  #   UrlAction       was `open`; each console URL is now rewritten into one
  #                   carrying the profile name, which UrlExecCommand turns into
  #                   a Brave profile, so two roles assumed at once never share
  #                   a cookie jar
  #   UrlExecCommand  the command that opens it, and the only reason any of this
  #                   lives in a file: unlike `--url-action`, it has no flag
  #
  # ProfileFormat names the Brave profile, and reads
  # `Production:AWSAdministratorAccess-051826724614`. AccountName arrives as a
  # breadcrumb (`Applications / Factbird / A / B / C`), which makes for a
  # profile label too long to read, so `splitList` and `last` keep the leaf
  # and `trim` drops the space the breadcrumb pads it with. An alias, which
  # carries no `/`, comes back from the split whole.
  #
  # The account id is what makes the name unique, and a cache refresh refuses a
  # duplicate outright: `Applications / Factbird / Production` exists under
  # both 051826724614 and 654654288373, and their leaves collide. It also keeps
  # a leaf shared by two portals apart, since no account id spans both.
  # AccountIdPad rather than AccountId, so an id starting in 0 keeps its
  # digits.
  #
  # `nospace` is not cosmetic. `aws-sso setup profiles` writes the name into
  # ~/.aws/config as `[profile <name>]` with no quoting, and botocore reads a
  # section header by splitting it the way a shell would and keeping it only
  # when two words come out. A name with spaces yields more, so the AWS CLI
  # drops that profile silently: it never appears in `aws configure
  # list-profiles`, and naming it returns `The config profile could not be
  # found`. Spaces also cost the interactive role prompt, which is
  # space-delimited.
  #
  # Single quotes because the template contains double ones, and aws-sso asks
  # for single quotes regardless: the value starts with `{`.
  #
  # DefaultRegion sits at the file level, the most generic of the four it can
  # be given at, below the SSO instance, the account and the role. Both portals
  # issue roles in eu-west-1, so neither needs its own. Without it aws-sso
  # falls back to us-east-1. It fills $AWS_REGION and $AWS_DEFAULT_REGION when
  # assuming a role and never overwrites a value the shell already carries.
  config = pkgs.writeText "aws-sso-config.yaml" (
    "SSOConfig:\n"
    + lib.concatMapStrings ssoEntry instances
    + ''
      DefaultSSO: Factbird
      DefaultRegion: eu-west-1
      ConsoleDuration: 720
      CacheRefresh: 168
      UrlAction: granted-containers
      UrlExecCommand:
          - ${openUrl}
          - "%s"
      LogLevel: error
      HistoryLimit: 10
      HistoryMinutes: 1440
      ProfileFormat: '{{ FirstItem .AccountName .AccountAlias | splitList "/" | last | trim | nospace }}:{{ .RoleName }}-{{ .AccountIdPad }}'
      FullTextSearch: true
    ''
  );
in {
  # aws-sso reads ~/.config/aws-sso per the XDG spec, but prefers ~/.aws-sso
  # whenever that older directory exists. Deleting it is what moves the
  # configuration here.
  home.file.".config/aws-sso/config.yaml".source = config;

  programs.zsh.envExtra = ''
    _aws_sso_instances=(${instanceList})

    # aws-sso hands out nothing once an SSO token has expired: `console` and
    # `eval` print `FATAL Must run aws-sso login` and stop, and `list` serves
    # a stale cache or none at all. Logging in first turns that dead end into
    # a browser prompt. It costs one keyring read per portal while the tokens
    # are still good, and `-L error` drops the "You are already logged in"
    # line without hiding the device code, which goes to stderr rather than
    # the log.
    #
    # A portal whose login fails costs its own roles and nothing else, so the
    # remaining ones still reach the picker. Only losing every portal is an
    # error.
    _aws_sso_login () {
      local entry failed
      for entry in "''${_aws_sso_instances[@]}"; do
        if ! ${pkgs.aws-sso-cli}/bin/aws-sso -S "''${entry%%:*}" login -L error; then
          print -u2 "aws-sso: no session for ''${entry#*:}, its roles are left out"
          failed=$((failed + 1))
        fi
      done
      (( failed < ''${#_aws_sso_instances[@]} ))
    }

    # One row per account/role pair, as `<portal> » <account> (AccountId) »
    # RoleName` followed by tabs, the ARN and the portal to assume it through.
    # aws-sso lists one SSO instance at a time, so the ARN alone does not say
    # which `-S` reaches it and the row has to carry that through. aws-sso
    # writes no CSV header, but it does end the CSV with a bare newline, so
    # `NF >= 5` is what separates a role from that last empty line.
    # AccountName is whatever ~/.config/aws-sso/config.yaml names the account
    # and is empty until someone writes it down, so the account column falls
    # back to the alias the SSO instance reports.
    #
    # Rows sort by portal, in the order aws-sso.nix lists them, and production
    # accounts head each portal's block: awk stamps each row with a rank that
    # `sort` orders on and `cut` then drops, so ties fall back to the string
    # fzf shows. `aws-sso list --sort` can do neither, since it orders one
    # printed field, knows nothing of the account column assembled here, and
    # sees a single portal per run.
    _aws_sso_rows () {
      local entry base=0
      for entry in "''${_aws_sso_instances[@]}"; do
        ${pkgs.aws-sso-cli}/bin/aws-sso -S "''${entry%%:*}" list --csv AccountName AccountAlias AccountIdPad RoleName Arn 2>/dev/null \
          | ${pkgs.gawk}/bin/awk -F, -v sso="''${entry%%:*}" -v label="''${entry#*:}" -v base="$base" 'NF >= 5 {
              account = ($1 == "" ? $2 : $1)
              rank = base + ((tolower(account) ~ /production/) ? 0 : 1)
              printf "%d\t%s » %s (%s) » %s\t%s\t%s\n", rank, label, account, $3, $4, $5, sso
            }'
        base=$((base + 2))
      done \
        | sort \
        | cut -f2-
    }

    # Pick one account/role pair and print its ARN and portal, tab separated.
    # fzf shows and matches field 1 only, which carries the portal label, so
    # typing an organisation's name narrows the list to it. Fields 2 and 3
    # pass through to the caller. A role that appears or disappears without
    # the token expiring needs an explicit `aws-sso -S <portal> cache`.
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
        | cut -f2,3
    }

    a () {
      local pick
      _aws_sso_login || return 1
      pick=$(_aws_sso_pick 'Assume' "''${1:-}")
      [[ -n "$pick" ]] || return 1
      eval "$(${pkgs.aws-sso-cli}/bin/aws-sso -S "''${pick##*$'\t'}" eval --arn "''${pick%%$'\t'*}")"
    }

    c () {
      local pick
      _aws_sso_login || return 1
      pick=$(_aws_sso_pick 'Console' "''${1:-}")
      [[ -n "$pick" ]] || return 1
      ${pkgs.aws-sso-cli}/bin/aws-sso -S "''${pick##*$'\t'}" console --arn "''${pick%%$'\t'*}"
    }
  '';
}
