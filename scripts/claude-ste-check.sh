# PreToolUse hook (Bash matcher). Runs ste-lint.py, from the asd-ste100-skill
# flake input, on the text a command is about to post: a gh/gh-axi
# --body-file, or a git commit -F. Exits clean, with nothing printed, when
# the command does not name a body file, so this never blocks a command it
# cannot evaluate.
set -euo pipefail

cmd=$(jq -re '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

path=$(grep -oE -- '(--body-file|-F)[[:space:]]+[^[:space:]]+' <<<"$cmd" | awk '{print $2}' | tail -1) || true
[ -n "$path" ] || exit 0
path="${path/#\~/$HOME}"
[ -f "$path" ] || exit 0

if ! out=$(python3 "$STE_LINT_SCRIPT" "$path" --baseline 0 2>&1); then
  echo "ste-lint found hard violations in $path:" >&2
  echo "$out" >&2
  echo "Fix the text, then rerun the same command." >&2
  exit 2
fi
