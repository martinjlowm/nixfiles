#!/usr/bin/env bash
# Lists open pull requests by @me that are waiting on the author. One qualifies
# when an unresolved review thread carries a last comment from a human other
# than you, or when the newest comment, review or thread reply on the pull
# request came from such a human. Every account GitHub types as a Bot is skipped
# on both counts, so botler, claude and datadog-official never list a pull
# request on their own. Select one to open in the browser.

set -euo pipefail

scope="all"
drafts="include"
for arg in "$@"; do
  case "$arg" in
    --this-repo) scope="repo" ;;
    --no-drafts) drafts="exclude" ;;
    -h|--help)
      echo "Usage: pr-attn [--this-repo] [--no-drafts]"
      echo "  (no flag)    Every open PR you authored, across all repositories"
      echo "  --this-repo  Only the repository of the working directory"
      echo "  --no-drafts  Skip draft pull requests"
      exit 0
      ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

me=$(gh api user --jq .login)
query="is:open is:pr author:@me sort:updated-desc"
if [[ "$scope" == "repo" ]]; then
  query+=" repo:$(gh repo view --json nameWithOwner -q .nameWithOwner)"
fi

pages=$(gh api graphql --paginate --slurp -f query='
query($q: String!, $endCursor: String) {
  search(query: $q, type: ISSUE, first: 50, after: $endCursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number title url isDraft
        repository { nameWithOwner }
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(last: 1) { nodes { author { login __typename } createdAt } }
          }
        }
        comments(last: 20) { nodes { author { login __typename } createdAt } }
        reviews(last: 20) { nodes { author { login __typename } submittedAt } }
      }
    }
  }
}' -f q="$query")

rows=$(echo "$pages" | jq -r --arg me "$me" --arg drafts "$drafts" '
  # A human other than you, the only kind of author who can be owed a reply.
  # A deleted account reports a null author and counts as a bot.
  def theirs: (.author.__typename // "Bot") == "User" and .author.login != $me;

  def ago:
    (now - fromdateiso8601) as $s
    | if   $s < 3600    then "\($s / 60      | floor)m"
      elif $s < 86400   then "\($s / 3600    | floor)h"
      elif $s < 2592000 then "\($s / 86400   | floor)d"
      else                   "\($s / 2592000 | floor)mo"
      end;

  [.[].data.search.nodes[]]
  | map(select(.number != null))
  | if $drafts == "exclude" then map(select(.isDraft | not)) else . end
  | map(
      ([.reviewThreads.nodes[]
        | select(.isResolved | not)
        | .comments.nodes[0]
        | select(. != null and theirs)] | length) as $waiting
      | ([(.comments.nodes[]      | {at: .createdAt,   author}),
          (.reviews.nodes[]       | select(.submittedAt != null) | {at: .submittedAt, author}),
          (.reviewThreads.nodes[] | .comments.nodes[]            | {at: .createdAt,   author})]
         | sort_by(.at) | last) as $last
      | select($waiting > 0 or ($last != null and ($last | theirs)))
      | (if $waiting > 0
         then ", \($waiting) thread\(if $waiting > 1 then "s" else "" end) on you"
         else "" end) as $threads
      | (if .isDraft then "draft  " else "" end) as $draft
      | {
          repo: .repository.nameWithOwner,
          number, url,
          at: $last.at,
          line: "#\(.number)  \($draft)\(.repository.nameWithOwner)  \(.title)  [\($last.author.login // "ghost") \($last.at | ago) ago\($threads)]"
        }
    )
  | sort_by(.at) | reverse
  | .[] | "\(.line)\t\(.repo)\t\(.number)\t\(.url)"
')

if [[ -z "$rows" ]]; then
  echo "No PRs waiting on you."
  exit 0
fi

count=$(echo "$rows" | grep -c '^')

echo "$rows" \
  | fzf \
      --no-sort \
      --delimiter=$'\t' \
      --with-nth=1 \
      --preview='gh pr view {3} --repo {2} --comments' \
      --preview-window=right:50%:wrap \
      --header="$count PR(s) waiting on you. Enter: open in browser (list stays open). Esc: quit" \
      --bind='enter:execute-silent(open {4})'
