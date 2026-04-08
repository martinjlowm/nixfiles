#!/usr/bin/env bash
# Firefighting frequency - reverts, hotfixes, and emergency commits
# Regular hotfixes suggest weak deploy processes or unreliable tests.
set -euo pipefail

since="${1:-1 year ago}"

git log --oneline --since="$since" | grep -iE 'revert|hotfix|emergency|rollback'
