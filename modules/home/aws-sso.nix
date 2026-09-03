# aws-sso-cli configuration
{pkgs, ...}: let
  # aws-sso runs this command itself rather than handing the URL to `open`, so
  # on macOS it needs the executable inside the bundle. The bundle directory
  # does not work.
  firefox = "${pkgs.firefox}/Applications/Firefox.app/Contents/MacOS/firefox";

  # Written out literally rather than generated from an attribute set, because
  # every YAML generator in nixpkgs sorts the keys and reindents to two spaces,
  # which would leave the file unrecognisable next to the one aws-sso's wizard
  # wrote. Three settings differ from that file:
  #
  #   AuthUrlAction   the login page belongs to no account, so it opens in the
  #                   ordinary browser rather than a container named for a role
  #   UrlAction       was `open`; each console URL is now rewritten into one the
  #                   Granted extension opens in a Firefox container named after
  #                   the profile, so two roles assumed at once never share a
  #                   cookie jar
  #   UrlExecCommand  the browser that opens it, and the only reason any of this
  #                   lives in a file: unlike `--url-action`, it has no flag
  #
  # ProfileFormat names the container, and reads
  # `Production:AWSAdministratorAccess-051826724614`. AccountName arrives as a
  # breadcrumb (`Applications / Factbird / A / B / C`), which makes for a
  # container label too long to read, so `splitList` and `last` keep the leaf
  # and `trim` drops the space the breadcrumb pads it with. An alias, which
  # carries no `/`, comes back from the split whole.
  #
  # The account id is what makes the name unique, and a cache refresh refuses a
  # duplicate outright: `Applications / Factbird / Production` exists under
  # both 051826724614 and 654654288373, and their leaves collide. AccountIdPad
  # rather than AccountId, so an id starting in 0 keeps its digits.
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
  # be given at, below the SSO instance, the account and the role. Without it
  # aws-sso falls back to us-east-1. It fills $AWS_REGION and
  # $AWS_DEFAULT_REGION when assuming a role and never overwrites a value the
  # shell already carries.
  config = pkgs.writeText "aws-sso-config.yaml" ''
    SSOConfig:
        Default:
            SSORegion: eu-west-1
            StartUrl: https://blackbird.awsapps.com/start
            AuthUrlAction: open
    DefaultRegion: eu-west-1
    ConsoleDuration: 720
    CacheRefresh: 168
    UrlAction: granted-containers
    UrlExecCommand:
        - ${firefox}
        - "%s"
    LogLevel: error
    HistoryLimit: 10
    HistoryMinutes: 1440
    ProfileFormat: '{{ FirstItem .AccountName .AccountAlias | splitList "/" | last | trim | nospace }}:{{ .RoleName }}-{{ .AccountIdPad }}'
    FullTextSearch: true
  '';
in {
  # aws-sso reads ~/.config/aws-sso per the XDG spec, but prefers ~/.aws-sso
  # whenever that older directory exists. Deleting it is what moves the
  # configuration here.
  home.file.".config/aws-sso/config.yaml".source = config;
}
