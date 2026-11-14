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

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status` (transparent, 0 tokens overhead)
<!-- /rtk-instructions -->

# Laptop sessions

On GitHub you act as the user, `martinjlowm`, so everything you post carries their name.
End every PR body, comment, review and reply you post there with the disclosure.

Use `gh-axi` for GitHub reads and writes from the shell. The `gh-axi` skill lists the cases
that stay on `gh`.

Image uploads use the `github-session` backend, documented in the `image-upload` skill's
`backends/github-session.md`.

