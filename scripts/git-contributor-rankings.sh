#!/usr/bin/env bash
# Contributor rankings by commit count
# Ranks all contributors to assess team structure and identify knowledge concentration.
# If one person has 60%+ commits, the project depends heavily on that individual.
set -euo pipefail

git shortlog -sn --no-merges
