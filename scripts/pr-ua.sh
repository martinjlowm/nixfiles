#!/usr/bin/env bash
# Lists open, non-draft PRs by @me that are not approved, don't have
# changes requested, and where reviewers still need prompting. Select one to
# open in the browser.

set -euo pipefail

prs=$(gh pr list \
  --author "@me" \
  --state open \
  --json number,title,url,isDraft,reviewRequests,reviews,reviewDecision \
  --limit 50 \
  | jq -r '
    [.[] | select(
      .isDraft == false
      and .reviewDecision != "APPROVED"
      and .reviewDecision != "CHANGES_REQUESTED"
      # Exclude PRs where reviewers are assigned and review is pending
      # (nothing for the author to do — ball is in reviewer court)
      and ((.reviewRequests | length) == 0)
    )] | to_entries[] | "\(.value.number)\t\(.value.title)\t\(.value.url)"
  ')

if [[ -z "$prs" ]]; then
  echo "No PRs need attention."
  exit 0
fi

selected=$(echo "$prs" \
  | fzf \
      --delimiter=$'\t' \
      --with-nth=1,2 \
      --preview='gh pr view {1} --comments' \
      --preview-window=right:50%:wrap \
      --header="Select a PR to open in browser")

url=$(echo "$selected" | cut -f3)
open "$url"
