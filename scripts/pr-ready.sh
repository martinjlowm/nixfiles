#!/usr/bin/env bash
# Lists open, non-draft PRs by @me that are approved, have no merge conflicts,
# and optionally filters by unresolved review comments.
#
# Usage:
#   pr-ready                 # approved, no conflicts (includes PRs with unresolved comments)
#   pr-ready --resolved      # approved, no conflicts, all comments resolved
#   pr-ready --unresolved    # approved, no conflicts, has unresolved comments

set -euo pipefail

filter="all"
for arg in "$@"; do
  case "$arg" in
    --resolved)   filter="resolved" ;;
    --unresolved) filter="unresolved" ;;
    -h|--help)
      echo "Usage: pr-ready [--resolved | --unresolved]"
      echo "  (no flag)    Show all approved PRs without merge conflicts"
      echo "  --resolved   Only PRs with all review comments resolved"
      echo "  --unresolved Only PRs with unresolved review comments"
      exit 0
      ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

repo_nwo=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

prs=$(gh pr list \
  --author "@me" \
  --state open \
  --json number,title,url,isDraft,reviewDecision,mergeable \
  --limit 100 \
  | jq -r '
    [.[] | select(
      .isDraft == false
      and .reviewDecision == "APPROVED"
      and .mergeable == "MERGEABLE"
    )]
  ')

if [[ "$(echo "$prs" | jq 'length')" -eq 0 ]]; then
  echo "No approved, conflict-free PRs found."
  exit 0
fi

# Check unresolved review threads per PR
declare -A pr_unresolved
while IFS= read -r number; do
  unresolved=$(gh api "repos/$repo_nwo/pulls/$number/reviews" --paginate --jq 'length' 2>/dev/null) || true
  # Use the review threads endpoint to count unresolved threads
  unresolved_count=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes { isResolved }
          }
        }
      }
    }' \
    -f owner="${repo_nwo%/*}" \
    -f repo="${repo_nwo#*/}" \
    -F number="$number" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null) || unresolved_count=0

  pr_unresolved[$number]="$unresolved_count"
done < <(echo "$prs" | jq -r '.[].number')

# Filter based on unresolved comments flag
filtered=""
while IFS=$'\t' read -r number title url; do
  uc="${pr_unresolved[$number]:-0}"
  case "$filter" in
    resolved)   [[ "$uc" -gt 0 ]] && continue ;;
    unresolved) [[ "$uc" -eq 0 ]] && continue ;;
    all)        ;;
  esac
  suffix=""
  if [[ "$uc" -gt 0 ]]; then
    suffix="  ($uc unresolved)"
  fi
  filtered+="#${number}  ${title}${suffix}"$'\t'"$url"$'\n'
done < <(echo "$prs" | jq -r '.[] | "\(.number)\t\(.title)\t\(.url)"')

if [[ -z "$filtered" ]]; then
  case "$filter" in
    resolved)   echo "No approved PRs with all comments resolved." ;;
    unresolved) echo "No approved PRs with unresolved comments." ;;
  esac
  exit 0
fi

count=$(echo -n "$filtered" | grep -c '^' || true)
header="$count approved, conflict-free PR(s)"
case "$filter" in
  resolved)   header+=" (all comments resolved)" ;;
  unresolved) header+=" (with unresolved comments)" ;;
esac

echo "$filtered" \
  | fzf \
      --no-sort \
      --ansi \
      --delimiter=$'\t' \
      --with-nth=1 \
      --preview='gh pr view $(echo {1} | grep -o "#[0-9]*" | tr -d "#") --comments' \
      --preview-window=right:50%:wrap \
      --header="$header — select to open in browser" \
  | { read -r selected || true
      url=$(echo "$selected" | cut -f2)
      [[ -n "$url" && "$url" == http* ]] && open "$url"
    } \
  || true
