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

# GitHub: mention nobody

Never write an `@handle` in a PR title, PR description, PR comment, review reply, issue, or
commit message. A mention notifies that account on the PR and again on the squash-merge
commit, and the people it reaches are usually the ones the change does not concern. Do not
name a person in prose either: attribution is not description.

When a handle is the subject matter, a CODEOWNERS line or a config value, keep it inside a
code span or a fenced block, where GitHub renders it inert. Before posting any body, grep it
with `grep -n "@[A-Za-z0-9]" <file>`: every hit must sit inside a code span or be gone.

# GitHub: open PRs as draft

Every PR you open is a draft: `gh pr create --draft`. Never promote one. `gh pr ready`, and
the `--ready` and `draft: false` forms of it, belong to the user, however finished the change
is and however green CI is. The draft flag is the handover, not a claim about the code: it
keeps the PR out of review queues and reviewer notifications until the user promotes it.
Likewise never flip a PR the other way. A ready PR stays ready, a draft stays draft.
