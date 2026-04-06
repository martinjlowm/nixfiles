# Usage: roadmap-sync - start an interactive roadmap sync session
set -e

PM_DIR="$HOME/projects/pm"
STATE_DIR="$PM_DIR/.state/roadmap-sync"

if [ ! -d "$PM_DIR" ]; then
  echo "Error: $PM_DIR does not exist"
  exit 1
fi

mkdir -p "$STATE_DIR"
mkdir -p "$STATE_DIR/projects"

grep -sq ".state/roadmap-sync" "$PM_DIR/.gitignore" 2>/dev/null || echo ".state/roadmap-sync/" >> "$PM_DIR/.gitignore"

if [ ! -f "$STATE_DIR/progress.txt" ]; then
  echo "# Progress Log - Roadmap Sync" > "$STATE_DIR/progress.txt"
  echo "Started: $(date)" >> "$STATE_DIR/progress.txt"
  echo "---" >> "$STATE_DIR/progress.txt"
fi

cd "$PM_DIR"
exec claude-pm --append-system-prompt-file "$HOME/.claude/agents/roadmap-sync.md" "Begin the roadmap sync workflow."
