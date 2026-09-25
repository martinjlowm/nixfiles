# Fetch what the PR-review pipeline reads about one pull request, once.
#
# The orchestrator runs this before it fans out, and every reviewer and
# verifier reads the files it writes instead of calling GitHub itself. Four
# reviewers fetching the same diff, metadata and three comment endpoints is
# about twenty tool calls per review, each one a model turn that re-reads the
# whole context; one run here is none.
#
# The identities match what the reviewers used: the app-token `gh` for the PR,
# the diff and the issue comments, and `gh-as-owner` for the two review
# endpoints, because a review left PENDING by an earlier run is visible only to
# its author and reading it as the bot silently omits it. Where the caller is
# already the owner, as on the laptop, `gh-as-owner` is plain `gh`.
#
# Usage:
#   agent-pr-digest <owner>/<name> <number>
#
# Writes $TMPDIR/pr-digest/<owner>-<name>-<number>-<sha12>/ (outside any
# checkout, so nothing here can be committed) and prints that directory as the
# first line of stdout, then a summary:
#
#   pr.md         metadata, the description, and the changed files with stats
#   diff.patch    the full diff, or a note saying why the API would not give one
#   files.txt     one changed path per line
#   comments.md   issue comments, reviews and inline comments, bodies in full
#   raw/*.json    the API responses, for any field the markdown leaves out
#
# Packaged as `agent-pr-digest` by scripts/default.nix here, and by mj-agents/
# devenv.nix for the fleet with its two GitHub identities.

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo 'usage: agent-pr-digest <owner>/<name> <number>' >&2
  exit 2
fi
repo=$1
number=$2

meta=$(gh pr view "$number" --repo "$repo" --json \
  number,title,body,author,headRefName,headRefOid,baseRefName,isDraft,state,additions,deletions,changedFiles,files)
sha=$(jq -r .headRefOid <<<"$meta")
dir="${TMPDIR:-/tmp}/pr-digest/${repo//\//-}-$number-${sha:0:12}"
rm -rf "$dir"
mkdir -p "$dir/raw"
printf '%s\n' "$meta" >"$dir/raw/pr.json"

# --paginate prints one JSON array per page; slurping and adding joins them.
gh-as-owner api --paginate "repos/$repo/pulls/$number/comments" | jq -s 'add // []' >"$dir/raw/review-comments.json"
gh-as-owner api --paginate "repos/$repo/pulls/$number/reviews" | jq -s 'add // []' >"$dir/raw/reviews.json"
gh api --paginate "repos/$repo/issues/$number/comments" | jq -s 'add // []' >"$dir/raw/issue-comments.json"

# GitHub refuses a diff past its size limits. Say so in the file rather than
# leaving it empty, and name the local equivalent, so no reader mistakes a
# refusal for a PR that changes nothing.
base=$(jq -r .baseRefName <<<"$meta")
if gh pr diff "$number" --repo "$repo" >"$dir/diff.patch" 2>"$dir/raw/diff.err"; then
  diff_note=""
  gh pr diff "$number" --repo "$repo" --name-only >"$dir/files.txt"
else
  diff_note="GitHub returned no diff ($(head -c 300 "$dir/raw/diff.err" | tr '\n' ' ')). Diff the checkout instead: git diff origin/$base...$sha"
  printf '%s\n' "$diff_note" >"$dir/diff.patch"
  jq -r '.files[].path' <<<"$meta" >"$dir/files.txt"
fi

jq -r --arg repo "$repo" --arg note "$diff_note" '
  "# \($repo)#\(.number): \(.title)",
  "",
  "Author: @\(.author.login)  State: \(.state)\(if .isDraft then " (draft)" else "" end)",
  "Head: \(.headRefName) @ \(.headRefOid)",
  "Base: \(.baseRefName)",
  "Size: \(.changedFiles) files, +\(.additions) -\(.deletions)",
  (if $note != "" then "", "Diff: \($note)" else empty end),
  "",
  "## Description",
  "",
  (if (.body // "") == "" then "(empty)" else .body end),
  "",
  "## Changed files (\(.changedFiles))",
  "",
  (if (.files | length) < .changedFiles
    then "Only \(.files | length) of \(.changedFiles) are listed here; files.txt has them all.", ""
    else empty end),
  "| + | - | path |",
  "| --- | --- | --- |",
  (.files[] | "| \(.additions) | \(.deletions) | \(.path) |")
' "$dir/raw/pr.json" >"$dir/pr.md"

{
  jq -r '
    "## Issue comments (\(length))",
    "",
    "Top-level comments, oldest first. Deferred design notes and measurements live here.",
    "",
    (if length == 0 then "None.", "" else empty end),
    (.[] | "### @\(.user.login), \(.created_at) (comment \(.id))", "", (.body // ""), "")
  ' "$dir/raw/issue-comments.json"
  jq -r '
    "## Reviews (\(length))",
    "",
    (if length == 0 then "None.", "" else empty end),
    (.[] | "### @\(.user.login), \(.state), \(.submitted_at // "not submitted") (review \(.id))",
      "",
      (if (.body // "") == "" then "(no body)" else .body end),
      "")
  ' "$dir/raw/reviews.json"
  jq -r '
    "## Inline review comments (\(length))",
    "",
    (if length == 0 then "None.", "" else empty end),
    (.[] | "### \(.path):\(.line // .original_line) (\(.side // "RIGHT")), @\(.user.login), \(.created_at) (comment \(.id), review \(.pull_request_review_id)\(if .in_reply_to_id then ", reply to \(.in_reply_to_id)" else "" end))",
      "",
      (.body // ""),
      "")
  ' "$dir/raw/review-comments.json"
} >"$dir/comments.md"

echo "$dir"
jq -r --slurpfile reviews "$dir/raw/reviews.json" \
  --slurpfile inline "$dir/raw/review-comments.json" \
  --slurpfile issue "$dir/raw/issue-comments.json" '
  "\(.title) by @\(.author.login), head \(.headRefOid[0:12]), base \(.baseRefName)",
  "\(.changedFiles) files, +\(.additions) -\(.deletions)",
  "\($issue[0] | length) issue comments, \($reviews[0] | length) reviews (\($reviews[0] | map(select(.state == "PENDING")) | length) pending), \($inline[0] | length) inline comments"
' "$dir/raw/pr.json"
echo "files: pr.md diff.patch files.txt comments.md raw/"
