#!/usr/bin/env bash
# Lists open, non-draft PRs by @me that have assigned reviewers but are not yet
# approved and don't have changes requested. Output is grouped by assignee/team.
# For each PR, suggests additional reviewers who recently touched the changed
# files. Select a PR with fzf to open in the browser.

set -euo pipefail

# Expects to be run from within the target repository
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository" >&2; exit 1; }

prs=$(gh pr list \
  --author "@me" \
  --state open \
  --json number,title,url,headRefName,createdAt,isDraft,reviewDecision,reviewRequests \
  --limit 100 \
  | jq -r '
    [.[] | select(
      .isDraft == false
      and .reviewDecision != "APPROVED"
      and .reviewDecision != "CHANGES_REQUESTED"
      and ((.reviewRequests | length) > 0)
    )]
  ')

if [[ "$(echo "$prs" | jq 'length')" -eq 0 ]]; then
  echo "No PRs pending review."
  exit 0
fi

total=$(echo "$prs" | jq 'length')

# Fetch all PR branches so we can diff locally
git fetch --quiet origin $(echo "$prs" | jq -r '.[].headRefName' | sed 's/^/refs\/heads\//' | tr '\n' ' ') 2>/dev/null || true

me=$(git config user.email || echo "")

# Convert calendar days ago to workdays (Mon-Fri)
workdays_since() {
  local days_ago=$1
  [[ "$days_ago" == "?" ]] && echo "?" && return
  local wd=0 i
  for (( i=1; i<=days_ago; i++ )); do
    local dow
    dow=$(date -v-"${i}d" +%u 2>/dev/null || date -d "$i days ago" +%u 2>/dev/null || echo "1")
    [[ $dow -le 5 ]] && (( wd++ ))
  done
  echo "$wd"
}

# Color code workdays: green <=2, yellow <=7, red >7
color_workdays() {
  local wd=$1
  local green=$'\033[32m' yellow=$'\033[33m' red=$'\033[31m' reset=$'\033[0m'
  if [[ "$wd" == "?" ]]; then
    echo "${wd}"
  elif [[ $wd -le 2 ]]; then
    echo "${green}${wd}wd${reset}"
  elif [[ $wd -le 7 ]]; then
    echo "${yellow}${wd}wd${reset}"
  else
    echo "${red}${wd}wd${reset}"
  fi
}

now=$(date +%s)
repo_nwo=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

# For each PR, fetch review request timestamps and compute days since opened/requested
declare -A pr_days_open
declare -A pr_reviewer_days
while IFS=$'\t' read -r number created_at; do
  created_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$created_at" +%s 2>/dev/null || date -d "$created_at" +%s 2>/dev/null || echo "$now")
  pr_days_open[$number]=$(( (now - created_epoch) / 86400 ))

  # Get timeline events to find when reviewers were requested
  timeline=$(gh api "repos/$repo_nwo/issues/$number/timeline" --paginate --jq '
    [.[] | select(.event == "review_requested") |
      { reviewer: (.requested_reviewer.login // .requested_team.slug // null), created_at }
    ] | group_by(.reviewer) | map({ (.[0].reviewer // "unknown"): (. | sort_by(.created_at) | last | .created_at) }) | add // {}
  ' 2>/dev/null) || true

  if [[ -n "$timeline" ]]; then
    while IFS=$'\t' read -r reviewer req_date; do
      [[ -z "$reviewer" || -z "$req_date" ]] && continue
      req_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$req_date" +%s 2>/dev/null || date -d "$req_date" +%s 2>/dev/null || echo "$now")
      days=$(( (now - req_epoch) / 86400 ))
      pr_reviewer_days["${number}_${reviewer}"]=$days
    done < <(echo "$timeline" | jq -r 'to_entries[] | "\(.key)\t\(.value)"')
  fi
done < <(echo "$prs" | jq -r '.[] | "\(.number)\t\(.createdAt)"')

# For each PR, find recent contributors to the changed files using local git history
declare -A pr_suggestions
while IFS=$'\t' read -r number branch; do
  # Get files changed in this PR vs origin/master
  files=$(git diff --name-only "origin/master...origin/$branch" 2>/dev/null) || true
  [[ -z "$files" ]] && continue

  current_reviewers=$(echo "$prs" | jq -r \
    --argjson n "$number" \
    '[.[] | select(.number == $n) | .reviewRequests[] | (.login // .slug // .name)] | join("|")')

  # Find recent authors who touched these files (last 6 months, up to 50 commits per file)
  contributors=$(echo "$files" | head -10 | xargs -I{} git log --since="6 months ago" -n 50 --format='%aN' -- {} 2>/dev/null \
    | { grep -v '^$' || true; } \
    | sort | uniq -c | sort -rn \
    | awk '{$1=""; print substr($0,2)}' \
    | { if [[ -n "$me" ]]; then grep -v "^$(git config user.name 2>/dev/null || echo '')$" || true; else cat; fi; } \
    | { if [[ -n "$current_reviewers" ]]; then grep -vE "^($current_reviewers)$" || true; else cat; fi; } \
    | head -3 \
    | paste -sd',' -)

  pr_suggestions[$number]="${contributors:-}"
done < <(echo "$prs" | jq -r '.[] | "\(.number)\t\(.headRefName)"')

# Get unique reviewers and fetch their total review workload
declare -A reviewer_workload
while IFS= read -r reviewer; do
  # Total open PRs where this person/team is a requested reviewer
  workload=$(gh search prs \
    --state open \
    --review-requested "$reviewer" \
    --json number \
    --limit 200 \
    -q 'length' 2>/dev/null) || workload="?"
  reviewer_workload[$reviewer]="$workload"
done < <(echo "$prs" | jq -r '[.[].reviewRequests[] | (.login // .slug // .name)] | unique[]')

# Build fzf input: grouped by reviewer, PR lines are selectable
fzf_input=""
while IFS=$'\t' read -r reviewer count; do
  workload="${reviewer_workload[$reviewer]:-?}"
  if [[ "$workload" != "?" && "$workload" -gt 0 ]]; then
    ratio=$(( count * 100 / workload ))
    if [[ $ratio -ge 50 ]]; then
      color=$'\033[32m' # green — high ratio, good
    elif [[ $ratio -ge 25 ]]; then
      color=$'\033[33m' # yellow — medium
    else
      color=$'\033[31m' # red — low ratio, bad
    fi
    reset=$'\033[0m'
    fzf_input+="$reviewer (${color}${count} mine / ${workload} total${reset}):"$'\n'
  else
    fzf_input+="$reviewer ($count mine / $workload total):"$'\n'
  fi
  while IFS=$'\t' read -r number title url; do
    days_open="${pr_days_open[$number]:-?}"
    days_waiting="${pr_reviewer_days[${number}_${reviewer}]:-?}"
    wd_open=$(workdays_since "$days_open")
    wd_review=$(workdays_since "$days_waiting")
    col_open=$(color_workdays "$wd_open")
    col_review=$(color_workdays "$wd_review")
    suggested="${pr_suggestions[$number]:-}"
    suffix=""
    [[ -n "$suggested" ]] && suffix="  -> $suggested"
    fzf_input+="  #${number}  ${title}  [opened ${col_open}, review ${col_review}]${suffix}"$'\t'"$url"$'\n'
  done < <(echo "$prs" | jq -r \
    --arg rev "$reviewer" \
    '[.[] | select(.reviewRequests[] | (.login // .name // .slug) == $rev)]
     | unique_by(.number) | sort_by(.number)[]
     | "\(.number)\t\(.title)\t\(.url)"')
  fzf_input+=$'\n'
done < <(echo "$prs" | jq -r '
  reduce .[] as $pr ({};
    reduce ($pr.reviewRequests[] | (.login // .name // .slug // "unknown")) as $reviewer (.;
      .[$reviewer] += [$pr]
    )
  )
  | to_entries | sort_by(-(.value | length), .key)[]
  | "\(.key)\t\(.value | length)"
')

# Write PR data to temp file for the action script
prs_file=$(mktemp)
action_script=$(mktemp)
trap 'rm -f "$prs_file" "$action_script"' EXIT
echo "$prs" > "$prs_file"

cat > "$action_script" << SCRIPT
#!/usr/bin/env bash
selected="\$1"
url=\$(echo "\$selected" | awk -F\$'\t' '{print \$2}')
if [[ -n "\$url" && "\$url" == http* ]]; then
  open "\$url"
else
  reviewer_name=\$(echo "\$selected" | sed 's/ (.*//')
  bullet_list=""
  while IFS=\$'\t' read -r number title pr_url; do
    bullet_list+="\- \${title} \${pr_url}"$'\n'
  done < <(jq -r \\
    --arg rev "\$reviewer_name" \\
    '[.[] | select(.reviewRequests[] | (.login // .name // .slug) == \$rev)]
     | unique_by(.number) | sort_by(.number)[]
     | "\(.number)\t\(.title)\t\(.url)"' "$prs_file")
  printf '%s' "\$bullet_list" | pbcopy
fi
SCRIPT
chmod +x "$action_script"

# Build summary of underutilized reviewers (low mine/total ratio, meaning they have capacity)
underutilized=""
while IFS=$'\t' read -r reviewer count; do
  workload="${reviewer_workload[$reviewer]:-?}"
  [[ "$workload" == "?" || "$workload" -eq 0 ]] && continue
  ratio=$(( count * 100 / workload ))
  if [[ $ratio -lt 25 ]]; then
    underutilized+="  $reviewer ($count/$workload = ${ratio}%)"$'\n'
  fi
done < <(echo "$prs" | jq -r '
  reduce .[] as $pr ({};
    reduce ($pr.reviewRequests[] | (.login // .name // .slug // "unknown")) as $reviewer (.;
      .[$reviewer] += [$pr]
    )
  )
  | to_entries | sort_by(.key)[]
  | "\(.key)\t\(.value | length)"
')

# Find active contributors from the past month who aren't already assigned as reviewers
my_name=$(git config user.name 2>/dev/null || echo "")
assigned_reviewers=$(echo "$prs" | jq -r '[.[].reviewRequests[] | (.login // .slug // .name)] | unique | join("|")')

active_contributors=$(git log --since="1 month ago" --format='%aN' \
  | { grep -v '^$' || true; } \
  | sort | uniq -c | sort -rn \
  | awk '{$1=$1; count=$1; $1=""; name=substr($0,2); print count "\t" name}' \
  | { if [[ -n "$my_name" ]]; then awk -F'\t' -v me="$my_name" '$2 != me' ; else cat; fi; } \
  | { if [[ -n "$assigned_reviewers" ]]; then awk -F'\t' -v revs="$assigned_reviewers" 'BEGIN{split(revs,a,"|"); for(i in a) r[a[i]]=1} !($2 in r)'; else cat; fi; } \
  | head -10 \
  | awk -F'\t' '{printf "  %s (%s commits)\n", $2, $1}')

header="Pending review: $total PRs — select a PR or group (Esc to quit)"
if [[ -n "$underutilized" ]]; then
  header+=$'\n'"Underutilized reviewers (your PRs are a small share of their queue):"$'\n'"$underutilized"
fi
if [[ -n "$active_contributors" ]]; then
  header+=$'\n'"Active contributors (past month, not assigned to your PRs):"$'\n'"$active_contributors"
fi

echo "$fzf_input" \
  | fzf \
      --no-sort \
      --tac \
      --ansi \
      --delimiter=$'\t' \
      --with-nth=1 \
      --no-preview \
      --header="$header" \
      --bind "enter:execute-silent($action_script {})+clear-query" \
  || true
