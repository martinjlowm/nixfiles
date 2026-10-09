---
name: comment-audit
description: Score the comments a diff adds with Jev, then decide what each one becomes. Use before committing code that adds comments, and when reviewing a pull request's comments.
---

# Comment audit

Code is the documentation. Names, types, extracted functions and assertions carry what the code
does; a comment carries only the **residue**, the fact no name, type or assertion can hold: an
external system's behaviour, a limit imposed from outside, a hazard, an invariant other code
relies on. The standard is the code-comments rule in the writing rules. This skill measures a
diff against it and turns each verdict into an edit.

Jev scores; you decide. Every signal is evidence about one comment, and the code it sits on
settles the question.

## 1. Score

```
node ~/.claude/skills/comment-audit/scripts/comment-score.ts --text [--base <ref>]
node ~/.claude/skills/comment-audit/scripts/comment-score.ts --text --diff <digest>/diff.patch --repo <checkout>
```

The first form audits your own work: every comment block added between the merge base with
`<ref>` (default `origin/HEAD`) and the working tree, committed or not. The second audits a
pull request from the review digest, reading files from a checkout at its head. Drop `--text`
for JSON.

It reads `TYPESAFE_API_KEY` and sends one Jev request per added comment block. When the key is
missing or Jev fails, apply step 2's table by hand to every added comment and say in your
report that the scorer did not run.

Each flagged block prints its actions, its signals and the comment:

| Signal | A high value means |
| --- | --- |
| `restates` | the names and statements below already say it |
| `history` | it narrates the past or the change that wrote it |
| `alternative` | it argues for the design against one not taken |
| `into-code` | a rename, extraction, type or assertion could carry it |
| `duplicate` | another comment in the file or diff states the same fact |
| `value` 0 to 2 | what a fluent reader loses on deletion: nothing, a convenience, a fact the code cannot show |
| `markers` | ticket numbers, finding ids or past-tense words matched in the text |

The per-file line shows added comment lines over added code lines. A ratio above about 0.3 says
the file explains itself in prose; read its kept comments again with that in mind.

## 2. Decide each flagged comment

| Action | The edit |
| --- | --- |
| `remove` | Delete it. If the code is unclear without it, the name is wrong: rename instead. |
| `into-code` | Make the code say it, then delete the comment. A shorthand becomes the full noun with its unit last (`x` becomes `heartbeat_age_ms`). A step label becomes a function named by its verb (`remove_widget_from_row`). An invariant becomes an assertion. |
| `move-to-commit` | Cut the history. It belongs in the commit message or the PR body, where `git blame` finds it next to the change. Keep any present-tense constraint the sentence carried. |
| `dedupe` | Keep the fact once, at the site where a reader makes the decision it governs, usually the code that enforces it. Delete it everywhere else. Both copies are flagged; choose one. |
| `trim` | Cut to the constraint. The defence of the design and the rejected alternative go to the PR body. |
| `keep` | Leave it. |

Read `uncertain` as "decide yourself". It lists only signals that could flip the decision: a
near-threshold one on a kept comment, a history marker the model scored low, or a removal that
rests on an unsure `value` alone.

Two kinds of comment are measured against a different reader:

- **A doc comment on a public item** speaks to a caller who sees the signature and not the body.
  It restates when it adds nothing to the signature, and it earns its place with units,
  errors, ownership or ordering the signature cannot express.
- **A user-facing schema description** (GraphQL, OpenAPI) is product documentation. Usage steps
  belong there; implementation detail does not.

Truth is a separate check. Jev scores whether a comment earns its place, never whether it is
correct, so a kept comment still has to match the code.

## 3. Close

**Authoring.** Apply the edits, run the repository's checks (renames change code, so behaviour
must still hold), and score again. Done when every flagged comment is edited or deliberately
kept, and each kept one carries a residue you can name in a sentence. Stop after two rounds;
a third score finds noise.

**Reviewing.** Each flagged comment you agree with becomes one finding with its edit as a
suggestion block, in the format the reviewing agent's file sets. The score is how you found
it, not why it should change: the finding argues from the code.

## Calibration

`scripts/labelled.json` holds labelled comments from FactbirdHQ/nest commits and the writing
rules. After changing a question or a threshold, run from `config/claude/skills/comment-audit`
in nixfiles

```
node scripts/comment-score.ts --calibrate scripts/labelled.json
node --test scripts/comments.test.ts
```

and compare agreement before and after. Add a case for every comment
the audit got wrong in practice.
