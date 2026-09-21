---
name: pr-description
description: Write and refine pull request titles and descriptions so they read as the final squash-merge commit message. Use when opening a PR, updating a PR body after new commits, or sweeping open PRs for stale descriptions ("refine my PRs", "fix the PR description", "document this contribution"). Also covers moving reviewer-only detail into a PR comment.
---

# PR description: write the commit message, not the changelog of the PR

Every PR title and description must describe the change **as it stands today**. On
squash-merge the description becomes the commit message, so write it for someone who reaches
it from `git blame` in a year with no access to the review conversation. They can already see
the diff. What they cannot recover is why anyone touched this code, so a description that
only summarises the diff has added nothing.

The test for any passage: **if it would read oddly in `git log`, it belongs in a PR comment
or nowhere.** These are the kernel's
[patch-submission conventions](https://www.kernel.org/doc/html/v4.17/process/submitting-patches.html#describe-your-changes)
applied to GitHub. The kernel drops everything else below the `---` line, where the tooling
strips it. Here that is a PR comment.

**Solve one problem per PR, and let the length tell you when you have not.** A body that
grows past a few short paragraphs is usually carrying two changes rather than one hard one.
The fix is the diff, not the prose. Say the PR wants splitting rather than stretching a
description to cover both.

Apply this skill to every PR you open or touch, not only when asked.

## The corpus is not the spec

Calibrating tone against `git log` works, and two rules here will look wrong when you do it,
because the merged history predates them. Follow the rules, not the corpus:

- **Titles are lowercase after the scope.** Older subjects capitalise (`fix(ingress/data-rollup):
  Use aws:PrincipalArn for Lambda role`). That is superseded.
- **Bodies carry no `@handle`.** Older ones do. Bare names are fine and always were, see
  [Never tag a person](#never-tag-a-person); the `@` is the part that was retired.

Everything else about how the merged bodies read is worth imitating.

## When to use

Opening a PR (`gh pr create --draft`, see [Draft until promoted](#draft-until-promoted)),
after pushing new commits to an open one, or on request.

Two modes. **Single PR** is the default: the one you just opened, or the one the user named.
**Sweep** is when the user asks to scan a set, "all open PRs authored by martinjlowm in
FactbirdHQ/nest". Enumerate them, apply the rules to each, then post the [report](#report).
Sweeps are the only mode that produce a report.

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
- **State the user-visible impact.** A fix says what the bug did to someone: the crash, the
  wrong number, the request that hung, the rows that went missing. "Fixes a race in
  `flush()`" is half a description; the half the reader came for is what the race cost them.
  A bug caught in review and never shipped still needs the sentence. Write the impact it
  would have had.
- **Write the change in the imperative.** "Refresh the token 60s before expiry", not "This PR
  makes the token refresh". For that sentence the subject is the code, never the pull
  request. The surrounding sentences are not bound by it, see [How it sounds](#how-it-sounds).
- **Verification belongs in a comment**, along with whatever you ran it against. Cut outright
  what CI guarantees: tests pass, clippy, rustfmt and biome clean, typechecks pass. The rest
  is true of a moment in review, not of the change, so a `git blame` reader stops to work out
  whether it is part of the feature. It is not. Move it and leave no link back. The one
  exception is a measured result that is itself the point of the change, written as a claim
  about the change rather than a test report.
- **Cut process noise:** rebases, conflict resolutions, resolved bot comments, which branch
  merged into which. Keep a stacking note only if it changes how today's diff reads.
- **Never append a Claude Code session link or agent attribution.** It records who typed the
  change, not what it does, and it dead-ends for anyone reading `git blame`. Strip it from
  bodies you touch, including PRs you open yourself.
- **Keep** issue references, screenshots and release-note sections. A reference the reader
  should follow goes inline as a full URL, where GitHub renders the title and the state:
  `https://github.com/FactbirdHQ/nest/pull/20189`, not `#20189`. Reserve the short form and
  the trailer position for the machine-read ones, last, one per line: `Closes: #1234`,
  `Fixes: AB#456`.
- **A ticket reference is never the description.** `JIRA-42` or `Closes #125` as the body,
  or a title that only names the ticket, moves the explanation into a system the reader may
  not be able to open and that outlives no migration.

## Never tag a person

**Never write an `@handle` outside a code span.** It is a notification: it pages that account
on the PR, on every edit, and again on the squash-merge commit that carries it into `git log`
forever.

Naming a person in prose is fine, and often the clearest way to say what happened. "Rune
reminded me that our stops windows actually uses SQS FIFO" is a better sentence than any
circumlocution around it. The `@` is what does the damage, not the name.

`FactbirdHQ/nest#20951` is the case this rule exists for. The title read
`chore(codeowners): narrow @martinjlowm to platform and InfluxDB paths`, the body carried two
handles, and a comment listed six more to state that their ownership was unchanged. Nine
notifications, and the one thing every recipient learned was that the PR did not concern them.

- **When a handle is the data, quote it as data.** A CODEOWNERS line, a team reference or a
  config value belongs in a code span or a fenced block, where GitHub renders it inert. A
  handle in backticks notifies no one. Never write one in running prose.
- **Never roll-call the unaffected.** Listing everyone a change does *not* touch is the worst
  form of this: every handle is a notification whose payload is "ignore me". Without the
  handles it is merely noise, so cut it there too.
- **Strip handles from every body you touch**, including PRs you opened earlier. Rewrite the
  sentence around the handle rather than deleting the sentence.

This binds PR comments and review replies too. Before posting, grep it: every hit must sit
inside a code span or be gone.

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

## How it sounds

The imperative binds the change sentence. It does not bind the paragraph around it, and
enforcing it everywhere produces the passive sludge this section exists to prevent: "was
asserted", "were confirmed", "was not run in this invocation". Three registers, one per job:

- **What the change does** is imperative, the code as subject. "Reject device ids that
  crashed sync."
- **What was wrong** is past tense, and takes whatever subject is true. "The shared cloud
  started running out of memory tonight."
- **What you did, measured, or do not know** is first person, always. "I did a `yarn cdk diff`
  on `mgmt/ms-device-provisioner` and `mgmt/mgmt-provisioning`, and only the second showed a
  diff." Hiding that actor is what makes verification prose read as machine-written. This
  register lives mostly in comments, where none of the commit-message constraints apply.

Four openers carry the paragraph order, and using them heads off the colon splices that
otherwise creep in ("The cost is backend load:", "The reason it was dropped:"):

| Opener | Job |
| --- | --- |
| `Now,` | Turns from the problem to the change. "Now, skip the cache insert while we sit above a high-water mark." |
| `Instead,` | Introduces the simpler alternative. Often "Instead of X, let's just Y". |
| `Mind that` | Introduces the cost or the caveat. "Mind that this is now a query, so the capacity used may increase because we have to look at the GSI." |
| `Turns out` | Opens a corrected assumption. "Turns out `aws:SourceArn` is only set if the API request is performed via a service on behalf of a resource." |

Contractions are in-voice, so don't expand them; an editing pass drifts formal on its own.
Hedges survive editing too. "presumably", "AFAIK", "I imagine", "I'm not sure if" are honest
and stay, and laundering one into confidence is a defect. That is not the padded hedging
that says nothing ("could potentially possibly"), which still goes.

## Write it to be read: less is more

Reviewer time is the cost of every line, so length must earn its place. Aim for the
shortest description that leaves a reader able to review the diff and, a year later, to see
why it exists. When a line is between staying and going, cut it.

- **Length is proportional to the change.** Match the message to the blast radius, not to
  the line count of the diff.
  - A typo or mechanical fix gets a title and no body.
  - An ordinary fix or feature gets the problem and the change. Two to five sentences,
    no headings.
  - A cutover, migration or breaking change gets those sentences first, then only the
    detail they cannot carry.
- **Headings in a body are a smell.** One problem needs prose and at most a short bullet
  list. Reaching for `## Background` / `## Changes` / `## Notes` usually means the body is
  doing a comment's job, or that the PR holds two changes.
- **Hard-wrap the body at 72 columns**, bullets at 70 with a two-space continuation indent.
  Markdown renders the joins as spaces, so the body reads the same on GitHub and stays
  readable indented under `git log`. Leave fenced blocks, tables and links unwrapped. The
  limit is for the commit message, so it binds the body and the title only, never a comment.
- Short, direct sentences, one idea each. Bullets over dense paragraphs.
- Rewrite any sentence that stacks several subjects, an em-dash aside, an "i.e." and a
  nested parenthesis. If it takes two readings, split it.
- Explain a term rather than coining one. "The cutoff dance" tells a reader nothing.
- Delete throat-clearing: "This PR", "In order to", "It is worth noting that", "Various
  improvements were made to".

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

**Every change states what it costs.** "4.2s to 180ms on 5k devices" is the benefit; what
was traded for it is the memory the batch holds, the staleness the cache allows, the error
path that now retries. No benchmark reports the cost, so a reviewer cannot weigh the change
without that sentence, and the rule is not special to optimisations. A guard costs the work
it skips, a retry costs duplicate effect, a narrowed permission costs whoever relied on the
broad one. `Mind that` is the sentence that carries it.

Name things as the code names them. An environment, account, tenant or config target gets the
identifier a reader can grep for, the entry it has in the module that declares it, not the
display name it goes by in conversation. Dates are absolute, `2026-07-28`, never "recently"
or "last month": `git log` is read years later and a relative date silently rebases onto the
reader's present.

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

Misplaced depth is the problem, not depth. Never delete any of it, relocate it, and link it
from the description in one line only if a reader of the description would want it. This
applies to PRs you open too. Editing someone else's PR is an edit, not a rewrite, so their
voice, diagrams and tables survive the move intact.

A comment never becomes a commit message, so none of the commit-message constraints apply to
it. Do not hard-wrap it, and do not ration its length. Let GitHub reflow the prose, and give
a walkthrough or a table the room it needs.

The body says what the change does. The comment shows it.

### Collapse the comment behind a summary

A comment carrying a walkthrough, a diagram or a verification run is long by design, and an
open block of it pushes the review conversation off the screen. Wrap every one of them in
`<details>`, so the reviewer sees a single line and expands what they want.

- **The `<summary>` is a call to action, not a label.** Name what expanding gives the
  reviewer and why they want it: `Expand for the cutover sequence and the rollback path`,
  `Expand for the verification run and the row counts it cross-checked`. `Details` and
  `More info` tell them nothing to decide on, so they expand everything or nothing.
- **Leave a blank line after the `</summary>` tag.** Without it GitHub renders the markdown
  inside as literal text, headings, tables and fenced blocks alike.
- **One `<details>` per topic.** A verification run, a worked example and a state diagram
  are three things a reviewer reaches for separately. Three blocks with three summaries let
  them open one; a single block makes them scroll past the other two.
- **Put nothing outside the blocks.** A sentence left above the first `<details>` is the
  part of the comment that was not worth collapsing, which means it belonged in the body.

````markdown
<details>
<summary>Expand for the cutover sequence and the rollback path</summary>

Writes land in both stores from this PR. Reads stay on the old store until the backfill
job reports 100%, so reverting this PR alone restores the previous behaviour and leaves
no data stranded.

</details>
````

### Correct the code, not the prose

A long-lived comment gets revised many times, and it will start keeping a record of its own
revisions: "two earlier versions of this section were wrong", "one assertion above has since
been corrected", "these figures are unchanged from the pre-review run". Cut all of it.

A correction earns its place when it changes what the reader should now believe about the
code or the decision. It does not when it only records what an earlier draft of the prose
claimed. Nobody read the draft. Make the correction in the surrounding sentences and let the
wrong version disappear.

An in-flight strikethrough is the opposite case and stays: `~Now, we also terminate early if
a hardware -> software mapping doesn't exist~ gave up on this because of failing tests` tells
a reviewer something true about the diff in front of them.

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

## Draft until promoted

**Open every PR with `gh pr create --draft`, and never take it out of draft.** `gh pr ready`,
and the `--ready` and `draft: false` forms of it, belong to the user. That holds however
finished the change is, however green CI is, and however plainly the description reads as
done. The draft flag is not a statement about the code, it is the handover: it keeps the PR
out of review queues, off `gh pr list --search draft:false` sweeps, and away from reviewer
notifications until the user says the work is theirs to look at. A description written to
these rules makes a draft look finished, which is exactly why this rule is here and not left
to judgement.

Refining an existing PR changes the title and body, nothing else: a ready PR stays ready, a
draft stays draft, and you never flip one in either direction. Asked to "open a PR" with no
mention of draft, it is still a draft, so say so in the line where you return the URL. The
user asking to promote is the one case for `gh pr ready`, and then only the PR they name.

## Titles

`<type>(<scope>): <description>`

- `type` is one of `feat`, `fix`, `chore`, `docs`.
- `scope` is the affected project directory. `chore(ui-app,ui-auth): ...` for two,
  `chore(*): ...` for many.
- **Imperative mood, lowercase, no trailing period.** `fix(api): reject empty device ids`,
  not `fixed empty device ids` or `rejects empty device ids`. It completes "this change will
  ...", matching `git log` and every generated message around it. The merged history
  capitalises here; that is superseded, and a refine pass never restores it.
- **Keep the whole line under 72 characters**, the description after the prefix nearer 50.
  A title that needs more is usually two changes.
- **Say what changes and, when it fits in 72 characters, why.** `fix(api): reject empty
  device ids` gives the what. `fix(api): reject device ids that crashed sync` gives both,
  and the title becomes searchable by the symptom as well as by the fix. State what the
  change does now, not what it set out to do.
- **No filenames.** `fix(sync): handle empty device ids`, not `fix(sync): update devices.rs`.
  The diff already says where the change is. The title has to say what it does.
- **No ticket alone** (`JIRA-42`, `#125`), and **no handle**: the title becomes the commit
  subject, and GitHub notifies on mentions in commit messages.
- On an existing PR, keep the current type and scope unless the diff shows they are wrong.

## Restraint

Act when a description:

- states a superseded approach, lists changes no longer in the diff, or omits a major change
  now present,
- is organised by the PR's history, or keeps a record of the prose's own revisions,
- buries a behavioural change, or leaves a breaking change to be inferred,
- fixes a bug without saying what the bug did to anyone,
- claims an optimisation with no number, or makes any change without naming what it costs,
- runs long, or sprouts headings, where the PR is really two changes,
- never says what problem the change solves, while the issue, commits or session do say what
  it is. If nothing does, that is a line in the report, not a guess in the body,
- restates the diff instead of describing the change, or stands on a ticket reference alone,
- carries an `@handle` outside a code span, or CI-verified and process noise,
- reports verification, or the fixture it ran against, or
- explains mechanism, defends a choice, or enumerates behaviour past the point the reader
  needs.

Reorder an accurate but hard-to-read description only when doing so surfaces something
buried.

When the diff is two unrelated changes, no single description can be honest about it. Write
the body around the one that dominates, state the other plainly rather than blending them,
and say in the report that the PR would read better split.

- **Verify every claim against the current diff**, and against the branch where the diff does
  not settle it. A body may name a default, a metric or an environment variable the diff only
  touches indirectly; read it out of the branch head rather than trusting the draft. Never
  state a change you cannot see.
- **Change titles and bodies only.** Never touch state, base branch, draft status, reviewers
  or labels. A sweep that promotes a draft has done something the user did not ask for and
  cannot undo quietly: the review requests are already out.
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
