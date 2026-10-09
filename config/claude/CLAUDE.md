<!-- rtk-instructions v3 (declared in nixfiles from rtk hooks/claude/rtk-awareness.md) -->
# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

## Meta Commands (always use rtk directly)

```bash
rtk gain              # Show token savings analytics
rtk gain --history    # Show command usage history with savings
rtk discover          # Analyze Claude Code history for missed opportunities
rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
```

## Installation Verification

```bash
rtk --version         # Should show: rtk X.Y.Z
rtk gain              # Should work (not "command not found")
which rtk             # Verify correct binary
```

⚠️ **Name collision**: If `rtk gain` fails, you may have reachingforthejack/rtk (Rust Type Kit) installed instead.

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status` (transparent, 0 tokens overhead)

Refer to CLAUDE.md for full command reference.
<!-- /rtk-instructions -->

# Laptop sessions

On GitHub you act as the user, `martinjlowm`, so everything you post carries their name.
Everything you post there, PR bodies, comments, reviews and replies, ends with
`<sub>Made with ❤️ by Claude (<model>)</sub>` on its own line, the model as your system prompt
names it, such as `Opus 5.5`. The agent-guard hook refuses a post without a disclosure.

Use `gh-axi` for GitHub reads and writes from the shell. The `gh-axi` skill lists the cases
that stay on `gh`.

Image uploads use the `github-session` backend, documented in the `image-upload` skill's
`backends/github-session.md`.

