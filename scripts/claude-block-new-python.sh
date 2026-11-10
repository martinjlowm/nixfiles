# PreToolUse hook (Write|Edit|Bash matcher). Blocks a session from authoring
# a new Python file. Running Python, and editing a .py file that already
# exists, pass. A .py name that only appears in a command's text, such as a
# heredoc body or a grep pattern, is not authoring, so only a redirect or a
# tee target counts in Bash.
set -euo pipefail

input=$(cat)
tool=$(jq -re '.tool_name // empty' <<<"$input")

paths=()
case "$tool" in
  Write | Edit)
    path=$(jq -re '.tool_input.file_path // empty' <<<"$input")
    if [[ $path == *.py ]]; then
      paths+=("$path")
    fi
    ;;
  Bash)
    cmd=$(jq -re '.tool_input.command // empty' <<<"$input")
    while IFS= read -r target; do
      [ -n "$target" ] && paths+=("$target")
    done < <(
      grep -oE '(>>?|\btee([[:space:]]+-a)?)[[:space:]]*[^[:space:];&|<>]+\.py\b' <<<"$cmd" |
        grep -oE '[^[:space:];&|<>]+\.py$'
    ) || true
    ;;
esac

for path in "${paths[@]}"; do
  [ -e "$path" ] && continue
  echo "ERROR: new Python scripts are not allowed. Use Node.js instead. ($path)" >&2
  exit 2
done
exit 0
