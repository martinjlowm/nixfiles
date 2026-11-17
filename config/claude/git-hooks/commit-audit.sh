# Scores the staged change with the comment-audit or scope-audit skill when
# Claude Code makes the commit.
#
#   claude-commit-audit comment                 (pre-commit)
#   claude-commit-audit scope <message-file>    (commit-msg)
#
# default.nix sets COMMENT_SCORER and SCOPE_SCORER.

if [[ "${CLAUDECODE:-}" != 1 ]]; then
  exit 0
fi

audit=$1
case $audit in
  comment)
    skill=comment-audit
    scorer=$COMMENT_SCORER
    diff_args=(--unified=0)
    ;;
  scope)
    skill=scope-audit
    scorer=$SCOPE_SCORER
    diff_args=(-M)
    ;;
  *)
    echo "claude-commit-audit: unknown audit '$audit'" >&2
    exit 2
    ;;
esac

# A merge commit carries changes that were reviewed on their own branches.
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

staged_diff=$work_dir/staged.patch
git diff --cached --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "${diff_args[@]}" >"$staged_diff"
if [[ ! -s $staged_diff ]]; then
  exit 0
fi

# The agent sees each report once per staged change. A commit of the same
# change after the report passes, because a kept finding is a valid decision.
stamp_dir=$(git rev-parse --git-path claude-audit)
stamp=$stamp_dir/$audit-$(sha256sum "$staged_diff" | cut -d' ' -f1)
if [[ -e $stamp ]]; then
  exit 0
fi

scorer_args=(--text --check --diff "$staged_diff" --repo "$(git rev-parse --show-toplevel)")
if [[ $audit == scope ]]; then
  git stripspace --strip-comments <"$2" >"$work_dir/body.md"
  scorer_args+=(--body "$work_dir/body.md")
fi

exit_needs_decision=3
status=0
report=$(node "$scorer" "${scorer_args[@]}" 2>&1) || status=$?

case $status in
  0)
    exit 0
    ;;
  "$exit_needs_decision")
    mkdir -p "$stamp_dir"
    touch "$stamp"
    {
      echo "$skill: the staged change has findings to decide."
      echo
      echo "$report"
      echo
      echo "Open the $skill skill and decide each finding by its rules."
      echo "Then commit again. A commit of the same staged change passes this check."
    } >&2
    exit 1
    ;;
  *)
    {
      echo "$skill: the scorer did not run, so this hook lets the commit through."
      echo "Review the staged change against the $skill skill by hand."
      echo
      echo "$report"
    } >&2
    exit 0
    ;;
esac
