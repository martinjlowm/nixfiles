#!/usr/bin/env bash
# Time-windowed contributor rankings
# Shows active contributors in recent months to detect if original builders have left.
# Compare against all-time rankings to spot knowledge gaps.
set -euo pipefail

since="${1:-6 months ago}"

git shortlog -sn --no-merges --since="$since"
