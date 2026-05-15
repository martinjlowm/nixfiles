# Spawn a loop + follow pane using WezTerm or tmux.
# Usage: mux-spawn <cwd> <session-name> <run-cmd> --- <follow-cmd>
#
# If WezTerm GUI is available, uses wezterm cli spawn + split-pane.
# Otherwise, falls back to tmux with a vertical split.

set -e

CWD="$1"; shift
SESSION_NAME="$1"; shift

# Split args on "---" into RUN_CMD and FOLLOW_CMD
RUN_CMD=()
FOLLOW_CMD=()
target=RUN_CMD
for arg in "$@"; do
  if [ "$arg" = "---" ]; then
    target=FOLLOW_CMD
    continue
  fi
  if [ "$target" = "RUN_CMD" ]; then
    RUN_CMD+=("$arg")
  else
    FOLLOW_CMD+=("$arg")
  fi
done

if [ ${#RUN_CMD[@]} -eq 0 ]; then
  echo "Error: no run command provided" >&2
  exit 1
fi

# Check for GUI availability
has_gui() {
  if [ "$(uname)" = "Darwin" ]; then
    [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_TTY:-}" ]
  else
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
  fi
}

# Try WezTerm first (requires running GUI instance)
if has_gui && wezterm cli list >/dev/null 2>&1; then
  LOOP_PANE_ID=$(wezterm cli spawn --new-window --cwd "$CWD" -- "${RUN_CMD[@]}")

  if [ ${#FOLLOW_CMD[@]} -gt 0 ]; then
    sleep 1
    wezterm cli split-pane --pane-id "$LOOP_PANE_ID" --bottom --percent 50 --cwd "$CWD" -- "${FOLLOW_CMD[@]}" 2>/dev/null || true
  fi
  exit 0
fi

# Fallback: tmux
if ! command -v tmux >/dev/null 2>&1; then
  echo "Error: No WezTerm GUI and tmux not found." >&2
  exit 1
fi

# Kill existing session with same name to avoid conflicts
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

tmux new-session -d -s "$SESSION_NAME" -c "$CWD" "${RUN_CMD[*]}"

if [ ${#FOLLOW_CMD[@]} -gt 0 ]; then
  tmux split-window -t "$SESSION_NAME" -v -p 50 -c "$CWD" "${FOLLOW_CMD[*]}"
fi

# Attach if we're in an interactive terminal, otherwise just report
if [ -t 0 ] && [ -t 1 ]; then
  exec tmux attach-session -t "$SESSION_NAME"
else
  echo "tmux session '$SESSION_NAME' created. Attach with: tmux attach -t $SESSION_NAME"
fi
