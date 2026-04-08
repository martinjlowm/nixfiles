#!/usr/bin/env bash
# Most-changed files in the past year
# Identifies the 20 files with highest churn - frequently modified files
# often indicate problematic code that teams avoid or constantly patch.
set -euo pipefail

since="${1:-1 year ago}"
count="${2:-20}"

git log --format=format: --name-only --since="$since" | sort | uniq -c | sort -nr | head -"$count"
