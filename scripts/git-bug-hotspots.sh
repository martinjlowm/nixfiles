#!/usr/bin/env bash
# Bug hotspots - files most frequently appearing in bug-fix commits
# Cross-reference with churn data: files on both lists represent
# highest-risk code that is repeatedly broken and patched.
set -euo pipefail

count="${1:-20}"

git log -i -E --grep="fix|bug|broken" --name-only --format='' | sort | uniq -c | sort -nr | head -"$count"
