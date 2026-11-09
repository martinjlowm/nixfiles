---
name: comment-audit
description: Score the comments a diff adds with Jev, then decide what each one becomes. Use before committing code that adds comments, and when reviewing a pull request's comments.
---

# Comment audit

Names, types, extracted functions and assertions carry what the code does. A comment carries
only the **residue**, the fact no name, type or assertion can hold. Examples are an external
system's behaviour, a limit imposed from outside, a hazard, or an invariant other code relies
on. The standard is the code-comments rule in the writing rules. This skill measures a diff
against it and turns each verdict into an edit.

Jev scores, and you decide. Every signal is evidence about one comment. The code it sits on
settles the question.

## 1. Score

```
node ~/.claude/skills/comment-audit/scripts/comment-score.ts --text [--base <ref>]
node ~/.claude/skills/comment-audit/scripts/comment-score.ts --text --diff <digest>/diff.patch --repo <checkout>
```

The first form audits your own work. It scores every comment block added between the merge
base with `<ref>` (default `origin/HEAD`) and the working tree, committed or not. The second
form audits a pull request from the review digest, reading files from a checkout at its head.
Drop `--text` for JSON.

The script reads `TYPESAFE_API_KEY` and sends one Jev request per added comment block. If the
key is missing or Jev fails, apply step 2's table by hand to every added comment. Say in your
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

The per-file line shows added comment lines over added code lines. If the ratio is above
about 0.3, the file explains itself in prose. Read its kept comments again with that in mind.

## 2. Decide each flagged comment

| Action | The edit |
| --- | --- |
| `remove` | Delete it. If the code is unclear without it, the name is wrong: rename instead. |
| `into-code` | Make the code say it, then delete the comment. A shorthand becomes the full noun with its unit last (`x` becomes `heartbeat_age_ms`). A step label becomes a function named by its verb (`remove_widget_from_row`). An invariant becomes an assertion. |
| `move-to-commit` | Cut the history. It belongs in the commit message or the PR body, where `git blame` finds it next to the change. Keep any present-tense constraint the sentence carried. |
| `dedupe` | Keep the fact once, at the site where a reader makes the decision it governs, usually the code that enforces it. Delete it everywhere else. Both copies are flagged, so choose one. |
| `trim` | Cut to the constraint. The defence of the design and the rejected alternative go to the PR body. |
| `keep` | Leave it. |

Read `uncertain` as "decide yourself". It lists only signals that could flip the decision:
- a near-threshold signal on a kept comment
- a history marker the model scored low
- a removal that rests on an unsure `value` alone

Two kinds of comment are measured against a different reader:

- **A doc comment on a public item** speaks to a caller who sees the signature and not the body.
  It restates when it adds nothing to the signature, and it earns its place with units,
  errors, ownership or ordering the signature cannot express.
- **A user-facing schema description**, such as GraphQL or OpenAPI, is product documentation.
  Usage steps belong there. Implementation detail does not.

Jev scores whether a comment earns its place, never whether it is correct. A kept comment
must still match the code.

## 3. Close

**Authoring.** Apply the edits, run the repository's checks, and score again. Renames change
code, so behaviour must still hold. You are done when every flagged comment is edited or
deliberately kept, and you can name each kept comment's residue in a sentence. Stop after two
rounds, because a third score finds noise.

**Reviewing.** Each flagged comment you agree with becomes one finding with its edit as a
suggestion block, in the format the reviewing agent's file sets. The finding argues from the
code, not from the score.

## Calibration

`scripts/labelled.json` holds labelled comments from FactbirdHQ/nest commits and the writing
rules. After changing a question or a threshold, run these from
`config/claude/skills/comment-audit` in nixfiles, and compare agreement before and after:

```
node scripts/comment-score.ts --calibrate scripts/labelled.json
node --test scripts/comments.test.ts
```

Add a case for every comment the audit got wrong in practice. To reword a question in
`comment-score.ts`, open the `typesafe-ai` skill. It covers writing Noul criteria and Score
levels.
