# Ensures a WezTerm mux is available for CLI commands.
# If wezterm cli is already connected, exits successfully.
# If no server is running and no GUI is available, starts wezterm-mux-server headlessly.

if wezterm cli list >/dev/null 2>&1; then
  exit 0
fi

# Check for GUI availability
has_gui() {
  if [ "$(uname)" = "Darwin" ]; then
    # On macOS, if we're in an SSH session there's no GUI
    [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_TTY:-}" ]
  else
    # Linux/other: check DISPLAY or WAYLAND_DISPLAY
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
  fi
}

if has_gui; then
  echo "Error: WezTerm is not running. Please start WezTerm first." >&2
  exit 1
fi

# No GUI, no server — start headless mux server
echo "Starting headless WezTerm mux server..." >&2
wezterm-mux-server --daemonize --config 'exit_behavior="Hold"'

# Wait for the server to be ready
for _ in $(seq 1 30); do
  if wezterm cli list >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.2
done

echo "Error: WezTerm mux server failed to start within 6 seconds" >&2
exit 1
