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

# Documentation: four modes, kept apart

Documentation committed to a repository follows the Diátaxis framework
(https://diataxis.fr/). Every page serves exactly one of four reader needs, and a page that
serves two is the failure this rule exists to catch.

- **Tutorial.** Teaches a beginner by walking one path that works. Explicit about everything,
  offers no choices, and never stops to explain. The reader is learning, not deciding.
- **How-to guide.** Gets a competent reader to a stated goal. Assumes they know the tools,
  branches on real conditions, and teaches nothing.
- **Reference.** Describes the machinery: options, attributes, outputs, file layouts. Austere,
  structured to mirror the thing it documents, and never instructive.
- **Explanation.** Says why the code is shaped this way, what was rejected, and what the
  history is. Never instructs, never catalogues.

Diagnose a page by the need it serves, not by its length. A reference table that has grown
steps is two pages. A tutorial that pauses to justify a design decision has lost the learner
and is missing an explanation page. Move the intruding material to the page that owns it
rather than deleting it.

Reference pages carry no guesses. Every option, attribute and default is read out of the code
before it is written down, and a name that is defined but never wired up is documented as
such rather than quietly listed with the rest.

Do not cite the framework or link it from the documentation itself. Naming the sections after
the four modes helps a reader navigate and is wanted; crediting the method that produced them
helps nobody who came to read the docs.

# Writing: run the unslop skill over it

The `unslop` skill applies to everything you write, not only when asked: documentation, commit
messages, PR titles and bodies, review replies, Slack drafts, and prose in code comments. Run
it before handing over anything you wrote, and again after any substantial rewrite.

The rules it enforces that get broken most often here: no em dashes, no colon splicing two
clauses together, active voice with the actor named, a concrete noun in every claim, sentence
case in headings, and no decorative emoji. A sentence that would survive unchanged in another
project's documentation says nothing about this one, so cut it.
