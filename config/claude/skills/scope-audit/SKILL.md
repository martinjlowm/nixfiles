---
name: scope-audit
description: Score whether a change solves one problem and how its functions are composed, with Jev, then plan the split or the restructure. Use before opening a pull request, and when reviewing one.
---

# Scope audit

A change earns review when it solves **one problem**, and code earns trust when its
**evidence** lives in names, types and seams rather than in prose. The opposite is a pull
request a reviewer cannot accept in part, and functions whose rules only a comment or the
caller's memory keeps. This skill measures a diff for both and turns each verdict into a
concrete edit: a split plan with an order, or a restructure small enough to suggest inline.

Jev scores; you decide. Every signal is evidence about one change or one function, and the
diff settles the question.

## What good looks like

These carry the standard. Reach for them when you write the fix.

- **One sentence of problem.** Every hunk serves it. A large change can still be one problem
  when its lines carry one invariant through many call sites, such as composing a service's
  configuration once and handing it down.
- **A constructor that rejects bad input**, so the type carries the invariant: a range type
  whose `new` returns `None` for `start > end`.
- **A decision forced at the type**: an error that can only be built as `client` or
  `server`, so every call site states which.
- **A guard whose destructor runs the second step**, so a pair such as reserve and release
  cannot drift: the caller holds a value, and dropping it settles.
- **A trait seam around I/O**, with one implementation per backend and one for tests, so
  tests drive real code instead of mocking modules.
- **Names with the unit last** (`retry_delay_ms_max`) and functions named by their verb,
  short enough to read whole.
- **An enum where a flag would be**, so each call site says what it means.

Lines a reviewer reads through their generator or as one repeated edit do not count against
scope: lockfiles and generated files, a rename or lint fix carried across the repository, a
move with no edits. The scorer separates them.

## 1. Measure

```
node ~/.claude/skills/scope-audit/scripts/scope-score.ts --text --body <description> [--base <ref>]
node ~/.claude/skills/scope-audit/scripts/scope-score.ts --text --body <Digest>/pr.md --diff <Digest>/diff.patch --repo <Local checkout>
```

The first form audits your own branch against the merge base with `<ref>` (default
`origin/HEAD`), working tree included; `<description>` is the PR body you are about to
open, as a file. The second audits a pull request from the review digest. Both read
`TYPESAFE_API_KEY`. When the key is missing or Jev fails, do steps 2 to 4 by reading the diff
and say in your report that the scorer did not run.

The first lines split the changed lines into generated, mechanical and hand-written, and give
a verdict:

| Verdict | Means |
| --- | --- |
| `one-problem` | The hand-written change is small, or every substantial concern is one. Go to step 4. |
| `propose-concerns` | Large enough that only the files can tell. Do step 2. |
| `split` | Two or more concerns each carry a substantial share. Do step 3. |

## 2. Name the concerns, then score again

Write 2 to 5 concerns to a JSON file, `[{"id": "<slug>", "statement": "<one sentence>"}]`,
from the description and your own reading of the diff, and run the same command with
`--concerns <file>`.

A concern is a **problem a reviewer could accept or reject on its own**, stated as what
changes and why, naming the symbols it touches. A helper, test or config value that only one
concern needs belongs to that concern. The same fix carried into two crates is one concern.
Jev assigns every hand-written file, or every hunk of a file over 120 hand-written lines, to
one concern, to `wiring` (plumbing between concerns) or to `unrelated`.

The output lists the lines per concern with each piece and its confidence, and an **order**:
`A before B` when B uses an item A defines, and `entangled` when two concerns use each
other's items. A piece below 0.5 confidence is yours to place by reading it.

A large `unrelated` group usually means a concern you did not name. Read its pieces, name
the concern, and score again before planning anything.

## 3. Plan the split as a stack

When the verdict is `split`, the plan is a **stack** of pull requests, one layer per
concern, bottom layer merging first, built with the `gh-stack` skill. Each layer is
reviewed and merged on its own while the ones above it wait, so a reviewer reads one problem
at a time and the author keeps working on top. Each layer carries:

- a branch name, a conventional title and the one-sentence problem it solves,
- its files and hunks, as `path:line` from the pieces,
- what it needs from the layers below it,
- how it is verified on its own: the test, benchmark or metric that shows it works before
  the next layer exists.

Layers follow the `before` edges, the owner below its user. An `entangled` pair resolves by
moving the shared items, usually a trait method or a type, into the lower layer. `wiring`
travels with the layer that needs it. `unrelated` lines become their own layer or leave the
branch. A concern with no edge to the others is no layer at all but its own pull request,
off the trunk, so it never waits on the stack.

A measurement or test harness that proves a later fix sits **below** it, so the fix is
judged against a baseline. A configuration knob sits **in** the layer whose behaviour it
switches.

End the plan with the commands that build it, bottom layer first:

```
gh stack init <bottom-branch>
gh stack add <next-branch>      # one per layer, in order
gh stack submit --auto
```

## 4. Restructure the flagged functions

The function list scores every non-test function the diff touches. Tests and benchmarks are
held to their own standard and left out.

| Action | The edit |
| --- | --- |
| `type-the-invariant` | Move the rule into a type: a guard value whose `Drop` or `finally` runs the second step, a newtype whose constructor rejects bad input, an enum for a state a flag tracked. Delete the comments that kept the rule. |
| `extract` | Name each responsibility as its own function and leave the original as the sequence of calls. Give the names. |
| `split-flag` | Two functions, or an enum the caller names, in place of the parameter the body branches on. |
| `merge-duplicate` | One helper for the repeated steps, with the signature that serves every copy. |
| `keep` | Leave it. |

`uncertain` lists signals near the threshold on functions long enough to matter: read the
function and decide. The same finding repeated across thin forwarding implementations of
one trait is one finding, at the trait.

Show the change where it fits. A restructure of 15 lines or fewer inside one hunk is a
```suggestion block. A larger one is a fenced sketch of the new types and signatures, with
the names, at the function it replaces.

## 5. Close

**Authoring.** Build the stack from step 3 before opening any PR, one commit series per
layer, then apply the function edits in the layer that owns each function, run the repository's checks, and measure again. Done
when the verdict is `one-problem` and every flagged function is edited or deliberately kept
with a reason you can name in a sentence.

**Reviewing.** The split plan goes in the review body. Each function finding is an inline
comment with its edit, in the format the reviewing agent's file sets. The score is how you
found it, not why it should change: the finding argues from the code.

## Calibration

`scripts/labelled.json` holds labelled PR descriptions and functions from FactbirdHQ/nest
and the author's own PRs. After changing a question or a threshold, run from
`config/claude/skills/scope-audit` in nixfiles

```
node scripts/scope-score.ts --calibrate scripts/labelled.json
node --test scripts/scope.test.ts
```

and compare agreement before and after. Reword a question with the `typesafe-ai` skill open,
and add a case for every verdict the audit got wrong in practice.
