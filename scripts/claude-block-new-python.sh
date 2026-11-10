# PreToolUse hook (Write|Edit|Bash matcher). Blocks a newly generated Python
# script. Running or editing an existing .py file, such as a vendored
# dependency's own script, passes through unaffected: the rule is about what
# this session authors, not about every file that happens to be Python.
set -euo pipefail

input=$(cat)
tool=$(jq -re '.tool_name // empty' <<<"$input")

path=""
case "$tool" in
  Write | Edit)
    path=$(jq -re '.tool_input.file_path // empty' <<<"$input")
    ;;
  Bash)
    cmd=$(jq -re '.tool_input.command // empty' <<<"$input")
    path=$(grep -oE '[^[:space:];&|><]+\.py' <<<"$cmd" | tail -1) || true
    ;;
esac

[ -n "$path" ] || exit 0
[ -e "$path" ] && exit 0

echo "ERROR: new Python scripts are not allowed. Use Node.js instead. ($path)" >&2
exit 2
