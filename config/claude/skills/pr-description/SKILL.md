---
name: pr-description
description: Write and refine pull request titles and descriptions so they read as the final squash-merge commit message. Use when opening a PR, updating a PR body after new commits, or sweeping open PRs for stale descriptions ("refine my PRs", "fix the PR description", "document this contribution"). Also covers moving reviewer-only detail into a PR comment.
---

# PR description: write the commit message, not the changelog of the PR

Every PR title and description must describe the change **as it stands today**. On
squash-merge the description becomes the commit message, so it is written for someone who
reaches it from `git blame` in a year with no access to the review conversation. They need
what the change does end-to-end, in its final form, and the problem it was there to solve.
Not how it got there.

That reader can already see the diff. What they cannot recover is why anyone touched this
code. A description that only summarises the diff has added nothing.

The test for any passage: **if it would read oddly in `git log`, it belongs in a PR comment
or nowhere.**

Apply this skill to every PR you open or touch, not only when asked.

## When to use

- Opening a new PR (`gh pr create`). Write the title and body to these rules from the start.
- After pushing new commits to an open PR. Bring the description back in line with the diff.
- On request: refine one PR, or sweep all open PRs authored by a user in a repo.

## Modes

**Single PR.** The default. The PR you just opened, or one the user named.

**Sweep.** The user asks to scan a set of PRs, for example "all open PRs authored by
martinjlowm in FactbirdHQ/nest". Enumerate them, apply the rules to each, then post the
report (see [Report](#report)). Sweeps are the only mode that produce a report.

```bash
gh pr list --repo <owner>/<repo> --state open --author <login> \
  --json number,title,url,body,headRefName
gh pr diff <number> --repo <owner>/<repo>
```

## The description is the final commit message

- **Describe only the end state.** A reader who never saw the PR evolve must come away with
  an accurate picture.
- **Order by importance, not chronology:** the problem, then the change, then the detail.
  Two or three lines carry the first two; everything else is detail and comes after.
- **Put every behavioural change at the top**, and say outright when the change breaks a
  caller, an API or a stored format. A behavioural change buried in a subsection is a defect
  in the description even when the sentence itself is correct. A breaking change the
  description merely implies is worse, because the reader who needed the warning was skimming.
- **Never structure the body around the PR's history.** No "Merged-in review follow-up",
  "Addressed feedback", "Round 2", "Update:". Fold what those changes *do* into the section
  they belong to, then delete the heading. A commit message does not record who asked for a
  change or when it landed.
- **Verification belongs in a comment, not the body.** Cut outright what CI already
  guarantees: tests pass, clippy, rustfmt and biome clean, typechecks pass. Everything else
  you ran is true of a moment in review, not of the change, and reads as noise from
  `git blame`: the manual procedure, the environment you ran it against, the counts you
  cross-checked, and what you could *not* verify yet. Move it to a PR comment. The one
  exception is a measured result that is itself the point of the change, written as a claim
  about the change rather than a test report. Leave no link back to the comment either. A
  commit-message reader has no use for it.
- **Keep what you tested against out of it**, including inside sentences that are otherwise
  about the change. The project, tenant, sample payload or row count you happened to run
  through is a fact about your verification. If the diff does not mention it, the body must
  not either. A `git blame` reader spends time working out whether it is part of the feature,
  and it is not.
- **Cut process noise:** rebases, conflict resolutions, resolved bot comments, which branch
  merged into which. Keep a stacking note only if it changes how today's diff reads.
- **Never append a Claude Code session link or agent attribution.** It records who typed the
  change, not what it does, and it dead-ends for anyone reading `git blame`. Strip it from
  bodies you touch, including PRs you open yourself.
- **Keep** issue references, screenshots and release-note sections. Put references last, one
  per line after the prose, as trailers: `Closes: #1234`, `Fixes: AB#456`.
- **A ticket reference is never the description.** `JIRA-42` or `Closes #125` as the body,
  or a title that only names the ticket, moves the explanation into a system the reader may
  not be able to open and that outlives no migration. State the problem and the change in
  the body; the reference is a pointer to more, not the answer.

## Never mention a person

**No PR text you write names a person.** Not the title, not the body, not a comment. A
`@handle` is a notification: it pages that account on the PR, on every edit, and again on the
squash-merge commit that carries it into `git log` forever. A bare name without the `@` pings
nobody but is still the wrong content, because who owns a path or wrote the earlier code is a
fact about people, not about the change.

`FactbirdHQ/nest#20951` is the case this rule exists for. The title read
`chore(codeowners): narrow @martinjlowm to platform and InfluxDB paths`, the body named two
handles, and a comment listed six more to state that their ownership was unchanged. Nine
notifications, and the one thing every recipient learned was that the PR did not concern them.

- **Write around the person.** "The `*` fallback made one account a code owner of all 9227
  tracked files" says everything the handle did. Use the role, the rule, or the path.
- **Never roll-call the unaffected.** Listing everyone a change does *not* touch is the worst
  form of this: every name is a notification whose payload is "ignore me".
- **When a handle is the data, quote it as data.** A CODEOWNERS line, a team reference or a
  config value belongs in a code span or a fenced block, where GitHub renders it inert. A
  handle in backticks notifies no one. Never write one in running prose.
- **Attribution is not description.** Who requested the change, who reviewed it, who wrote the
  code being fixed: all of it is process, and the commit-message rule above already cuts it.
- **Strip mentions from every body you touch**, including PRs you opened earlier. Rewrite the
  sentence around the handle rather than deleting the sentence.

The same rule binds PR comments, review replies, and anything else this skill has you post to
GitHub. Before posting a title or a body, grep it: every hit must sit inside a code span or
be gone.

```bash
grep -n "@[A-Za-z0-9]" <file>
```

## Open on the problem

The diff shows what changed. It cannot show what was wrong, so the description must. That
sentence is the one a `git blame` reader came for, so lead with it.

- **One or two sentences of problem, before the change.** What broke, what was missing, what
  the old behaviour cost. Written as a fact about the code, not as a story about the week.
- **Then the change, in one sentence**, as the answer to it. Detail after that.
- **Name the constraint that shaped the change** where the code would otherwise look wrong:
  the upstream bug being worked around, the format that cannot be broken, the limit being
  respected. A rejected alternative earns a clause only when a future reader would otherwise
  "fix" the code back to it.
- **Link the source** when the change follows from something outside the repo: a spec
  section, an upstream issue, a vendor doc. That link is the one piece of process a
  commit-message reader does want, because they cannot reconstruct it.
- **Don't pre-argue.** Defending a decision nobody has questioned, or weighing the
  alternatives on their merits, belongs in review. The body states the reason; it does not
  litigate it.
- **Never invent the problem.** The diff does not contain it. Take it from the linked issue,
  the branch's own commits, or the session that produced the change; if none of those settle
  it, ask rather than reconstruct a plausible motive. A confident wrong reason is worse in
  `git blame` than no reason, because the next reader builds on it.

`FactbirdHQ/nest#20608` opens on exactly this shape:

> Approving a manually-gated production deployment means approving blind: the gate names
> which projects will deploy, not what they will change.
>
> Run `cdk diff` before the approval gate and emit it as workflow annotations.

Problem, then change, in two sentences, before the diagram, the table and the mechanism
that make up the rest of that body.

## Write it to be read: less is more

Reviewer time is the cost of every line, so length must earn its place. Aim for the
shortest description that leaves a reader able to review the diff and, a year later, to see
why it exists. When a line is between staying and going, cut it.

- **Length is proportional to the change.** A typo fix needs a title and no body. A cutover,
  a migration or a behavioural change needs the problem stated. Match the message to the
  blast radius, not to the line count of the diff.
- Hard-wrap prose at 72 columns. Markdown renders the joins as spaces, so the body reads the
  same on GitHub and stays readable indented under `git log`. Leave fenced blocks, tables and
  links unwrapped.
- Short, direct sentences, one idea each. Bullets over dense paragraphs.
- Rewrite any sentence that stacks several subjects, an em-dash aside, an "i.e." and a
  nested parenthesis. If it takes two readings, split it.
- Explain a term rather than coining one. "The cutoff dance" tells a reader nothing.
- Delete throat-clearing: "This PR", "In order to", "It is worth noting that", "Various
  improvements were made to".
- Depth is not the problem, misplaced depth is. Worked examples and diagrams are depth, and
  they belong in the comment, not the body. Never delete them, relocate them. Editing
  someone else's PR is an edit, not a rewrite, so their voice, diagrams and tables survive
  the move intact.

### Stop at what it does

Over-explaining a change you understand well is the most common way a body doubles in length
without helping anyone.

- **Answer "what", once.** State the change and the consequence that matters. Do not walk
  through every case that follows from it, or every call site that inherits it; a reader who
  needs exhaustive behaviour reads the diff.
- **A summary of the diff is not a description.** Enumerating the files touched and the
  functions renamed reads as thorough while adding nothing a reader could not derive from the
  change itself, and it crowds out the problem statement, the one thing they could not.
  Watch for this hardest when writing from the diff alone, which is the natural default and
  the wrong one: every line that only restates the diff is a line to cut.
- **State the assumption, not the arithmetic.** When the change narrows scope, the
  load-bearing sentence is the invariant that makes the narrower scope sufficient, not the
  cost it saves or the fan-out it avoids.
- **Mechanism that leaves no trace in behaviour is not description.** How an interpreter is
  pinned, why an import list is short, which language constructs a file must avoid: this is
  code-comment material. In the body a file gets one line, saying what it does.

### Be concrete

Every claim names the thing it is about: a symbol, a file, a number, a threshold. A
sentence that survives with any noun substituted in says nothing.

| Instead of | Write |
| --- | --- |
| Improved session handling. | Tokens now refresh 60s before expiry instead of on the 401 retry. |
| Fixed a race condition. | `flush()` awaited the write it just queued, so two concurrent callers could interleave. It now holds the lock across queue-and-write. |
| Various performance improvements. | Dropped the per-row `SELECT` in `sync_devices`, one batched query instead of N. 4.2s to 180ms on 5k devices. |
| Refactored for clarity. | Split `handler.rs` into `parse.rs` and `dispatch.rs`. No behavioural change. |
| Added `[Required]` to `ReservationRequestModel`. | Reservations were accepted without a phone number, crashing the downstream dispatch job. `PhoneNumber` is now required on `/reservations`; that breaks existing callers, so the endpoint is versioned to 2.0. |

The right-hand column is not longer for its own sake. It is the only version a reviewer
can act on.

Name things as the code names them. An environment, account, tenant or config target gets the
identifier a reader can grep for, the entry it has in the module that declares it, not the
display name it goes by in conversation.

## Additional detail goes in a PR comment

Some material is worth keeping but does not belong in a commit message:

- how the approach changed mid-flight, and what a review round found,
- merge and conflict notes,
- deep rationale a reviewer needs now but posterity will not. The split is durability, not
  depth. The reason the change exists and the constraint that shaped it stay in the body
  however long they take to state. The survey of options, the benchmark that settled a
  choice, and the reply to a reviewer's objection go here,
- **verification**: what you ran, against which environment or fixture, the numbers you
  cross-checked, and what is still unverified,
- **worked examples**, walkthroughs and sample payloads,
- **diagrams** of state, flow or layout.

Do not delete any of it. Move it into a comment on the PR, and link it from the description
in one line only if a reader of the description would want it. This applies to PRs you open
too. Longer context for the reviewer belongs in a comment on the PR you just created, never
in the body.

The body says what the change does. The comment shows it.

### Diagram state, don't narrate it

Prose is bad at state machines, migrations, cutovers, ordering and fan-out. When a change
is state-heavy, an ASCII diagram in a fenced block replaces a paragraph the reviewer has to
hold in their head.

Guide the diagram: label the arrows with *why*, mark what this PR changes, and keep it to
the smallest picture that carries the idea.

```
before             during (this PR)          after (#20412)
──────             ────────────────          ──────────────
app                app                       app
 ├─write─> old      ├─write─> old  ◄─ kept    └─write─> new
 └─read──> old      ├─write─> new     for      └─read──> new
                    └─read──> old     rollback
                              ▲
                              └─ reads stay on old until the
                                 backfill job reports 100%
```

Rules of thumb:

- One diagram per concept, next to the passage it explains.
- Annotate, don't decorate. An arrow without a label is a line.
- If the diagram needs a paragraph to interpret, it has failed. Redraw it smaller.
- Skip it entirely when the change is linear. A diagram of a two-step flow is noise.

The description keeps at most one line pointing at it, "Cutover sequencing and rollback
path: <comment link>", and only when a `git blame` reader would follow it.

```bash
gh pr comment <number> --repo <owner>/<repo> --body-file <file>
```

## Titles

`<type>(<scope>): <description>`

- `type` is one of `feat`, `fix`, `chore`, `docs`.
- `scope` is the affected project directory. `chore(ui-app,ui-auth): ...` for two,
  `chore(*): ...` for many.
- **Imperative mood, lowercase, no trailing period.** `fix(api): reject empty device ids`,
  not `fixed empty device ids` or `rejects empty device ids`. It completes "this change will
  ...", matching `git log` and every generated message around it.
- **Keep the whole line under 72 characters**, the description after the prefix nearer 50.
  A title that needs more is usually two changes.
- State what the change does now, not what it set out to do.
- A title that names only a ticket (`JIRA-42`, `#125`) is not a title.
- **No handle in the title.** It becomes the commit subject, and GitHub notifies on mentions
  in commit messages. Name the paths or the rule the change touches instead.
- On an existing PR, keep the current type and scope unless the diff shows they are wrong.

## Restraint

Act when a description:

- states a superseded approach,
- lists changes no longer in the diff,
- omits a major change now present,
- is organised by the PR's history,
- buries a behavioural change, or leaves a breaking change to be inferred,
- never says what problem the change solves, while the issue, commits or session do say what
  it is. If nothing does, that is a line in the report, not a guess in the body,
- restates the diff instead of describing the change,
- stands on a ticket reference alone,
- names a person, or carries an `@handle` outside a code span,
- carries CI-verified or process noise,
- reports verification, or the fixture it ran against, or
- explains mechanism, defends a choice, or enumerates behaviour past the point the reader
  needs.

Reorder an accurate but hard-to-read description only when doing so surfaces something
buried.

When the diff is two unrelated changes, no single description can be honest about it. Write
the body around the one that dominates, state the other plainly rather than blending them,
and say in the report that the PR would read better split.

- **Verify every claim against the current diff.** Never state a change you cannot see.
- **Change titles and bodies only.** Never touch state, base branch, draft status, reviewers
  or labels.
- When genuinely unsure, leave the PR alone and say so in the report.

```bash
gh pr edit <number> --repo <owner>/<repo> --title <title> --body-file <file>
```

## Report

Sweeps only. Post to the Slack channel the user named (`#pr-refinement` for the nest sweep):

- one line per changed PR, with number, link, and the reason it was stale,
- any content moved into a PR comment,
- the count left unchanged.

Keep it skimmable. The detail lives on the PRs.

- Post nothing when no PR needed changing. Note the quiet run in the session instead.
- If Slack is unreachable, report in the session and say the post could not be made.
