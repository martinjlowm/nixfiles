#!/usr/bin/env bash
# Commit velocity over time
# Charts monthly commit counts across entire repository history.
# Reveals team momentum, staffing changes, and release patterns.
set -euo pipefail

git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c
