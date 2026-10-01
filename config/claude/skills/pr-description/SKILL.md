---
name: pr-description
description: Write and refine pull request titles and descriptions so they read as the final squash-merge commit message. Use when opening a PR, updating a PR body after new commits, or sweeping open PRs for stale descriptions ("refine my PRs", "fix the PR description", "document this contribution"). Also covers the reviewer comment that opens on the merge danger and carries the evidence and reviewer-only detail.
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
- **Bodies carry no `@handle`.** Older ones do. Bare names are fine and always were; the
  `@` is the part that was retired.

Everything else about how the merged bodies read is worth imitating.

## When to use

Opening a PR, after pushing new commits to an open one, or on request.

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
- **Evidence and verification belong in the comment.** Cut outright what CI guarantees:
  tests pass, clippy, rustfmt and biome clean, typechecks pass. A named test that failed
  before and passes now is evidence, not a CI claim, and goes in the comment. The rest
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
  `https://github.com/FactbirdHQ/nest/pull/20189`, not `#20189`. The trailer position is
  for the issues the PR resolves, see [Cite the report behind it](#cite-the-report-behind-it).
- **A ticket reference is never the description.** `JIRA-42` or `Closes #125` as the body,
  or a title that only names the ticket, moves the explanation into a system the reader may
  not be able to open and that outlives no migration.

## Never tag a person

The global "mention nobody" rule binds titles, bodies and comments. Naming a person in prose is
often the clearest way to say what happened. "Rune reminded me that our stops windows actually
uses SQS FIFO" is a better sentence than any circumlocution around it.

`FactbirdHQ/nest#20951` is the case the rule exists for. The title read
`chore(codeowners): narrow @martinjlowm to platform and InfluxDB paths`, the body carried two
handles, and a comment listed six more to state that their ownership was unchanged. Nine
notifications, and the one thing every recipient learned was that the PR did not concern them.

- **Never roll-call the unaffected.** Listing everyone a change does *not* touch is the worst
  form of this: every handle is a notification whose payload is "ignore me". Without the
  handles it is merely noise, so cut it there too.
- **Strip handles from every body you touch**, including PRs you opened earlier. Rewrite the
  sentence around the handle rather than deleting the sentence.

## Open on the problem

Lead with what was wrong. It is the sentence a `git blame` reader came for.

- **One or two sentences of problem, before the change.** What broke, what was missing, what
  the old behaviour cost. Written as a fact about the code, not as a story about the week.
- **Then the change, in one sentence**, as the answer to it. Detail after that.
- **Name the constraint that shaped the change** where the code would otherwise look wrong:
  the upstream bug being worked around, the format that cannot be broken, the limit being
  respected. A rejected alternative earns a clause only when a future reader would otherwise
  "fix" the code back to it.
- **Link the source** when the change follows from something outside the repo: a spec
  section, an upstream issue, a vendor doc. That link is the one piece of process a
  commit-message reader does want, because they cannot reconstruct it. The report that
  motivated the change is never optional, see
  [Cite the report behind it](#cite-the-report-behind-it).
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

### Cite the report behind it

Every PR references a GitHub issue for the problem it addresses. The problem sentence says
what was wrong, and the issue is the evidence that someone hit it, so a `git blame` reader
can follow it back to the conversation and the people the change was for. A support ticket,
an incident, an alert or a review finding is where the problem surfaced, not the issue that
tracks it, so it never stands in for one.

- **Look before you write.** The issue in the prompt or the session, links in the branch's
  commits, an issue that `gh issue list --repo <owner>/<repo> --state all --search
  "<symptom>"` finds. Note the Zendesk ticket, incident or alert that started the work as
  well: the issue links it.
- **A non-issue source goes inline** in the problem sentence, as a full URL: the Zendesk
  ticket, the Dependabot alert, the incident, the review comment. It sits beside the issue
  reference, never in place of it, and a PR keyword cannot close any of them.
- **An issue the PR resolves goes in a trailer.** End the body with one `Closes` line per
  resolved issue, full URL, nothing after them:

  ```
  Closes https://github.com/FactbirdHQ/nest/issues/21286
  Closes https://github.com/FactbirdHQ/nest/issues/21290
  ```

  An issue the PR only advances, without resolving it, goes inline instead. A `Closes`
  line on it would close it on merge. A prompt that prescribes its own trailer form, such
  as `Closes #<task>` for a pipeline that matches on it, wins over this one.
- **When no issue exists, open one yourself** in the PR's repository, FactbirdHQ/nest for
  nest work, before creating the PR. That holds whenever the search above finds no issue,
  including when a support ticket, incident or alert already reports the problem; the
  issue links that source. Title it with the problem, not the fix. The body states what is
  wrong, what it costs and where it shows, taken from the session and the commits under the
  same rule as never inventing the problem: if they do not settle it, ask rather than file
  a guess. Add no labels, assignees or project, and no `@handle`. Then close it from the PR
  with a `Closes` line.
- **Every issue is triaged with a type.** This is the issue's Type, not one of the
  organisation's custom issue fields such as Priority. An issue without its type set sits
  outside the boards and queries that sort the work, so set it on every issue you file and
  on any existing issue the PR cites that has none. The type is `Task` unless the issue
  plainly is something else: `Bug` for an unexpected problem in shipped behaviour, `Feature`
  for new functionality someone asked for. Leave a type someone already set alone.
- **The issue proves its claim.** An issue states that something is wrong, so it carries the
  evidence a reader needs to believe that without reproducing it. One you file includes it
  from the start. An existing issue that states the problem without it gets the evidence
  as a comment from you before the PR cites it, and its body stays the author's.
  - Draw the evidence with the [`show-me`](#show-the-shape-dont-narrate-it) views: a `diff`
    of the expected against the actual output, the call tree that reaches the failure with
    the `file:line` of each frame, pseudocode of the branch that goes wrong, a Mermaid
    sequence of the race. An issue is not a commit message, so Mermaid and full-width
    blocks are fine here.
  - Back the view with the raw proof it summarises: the failing test and its output, the
    log line, the query and its result, a screenshot uploaded with `image-upload`. A view
    with nothing behind it is a claim drawn as a picture.
  - Evidence from a support ticket is the product behaviour it shows, reproduced on our
    side where possible. The customer's data stays in Zendesk.
- **A support ticket stays in its system.** An issue filed from a Zendesk ticket links the
  ticket and describes the problem in the product's terms. Customer names, contact details
  and the conversation itself stay in Zendesk.

```bash
gh issue create --repo <owner>/<repo> --title "<problem>" --body-file <file> --type Task
gh issue edit <number> --repo <owner>/<repo> --type Task   # an existing issue with no type
```

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
- Bullets over dense paragraphs.
- Explain a term rather than coining one. "The cutoff dance" tells a reader nothing.
- Delete "This PR" and "Various improvements were made to". `unslop` covers the rest of the
  sentence-level cuts.

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

Every claim names the thing it is about: a symbol, a file, a number, a threshold.

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

## Show the shape, don't narrate it

Prose is bad at shape: which call now runs before which, which file took over which
responsibility, which field a contract gained, which component now owns the state. A
paragraph that walks through it makes the reviewer rebuild the picture in their head. Read
the `show-me` skill (`~/.claude/skills/show-me/SKILL.md`) and draw the picture with its
views instead: pseudocode, a call tree, a component tree, a shallow file tree, a type, a
table or an endpoint contract.

- **A view replaces a paragraph. It never sits beside one.** When the body carries a view,
  cut the sentences it makes redundant. The problem and the change sentence still come
  first, because no view can say why.
- **One view, two at most, and only where the change has a shape.** A typo or an ordinary
  fix gets none, per [the length rule](#write-it-to-be-read-less-is-more). A change that
  reroutes a call path, moves responsibilities between files or changes a contract gets the
  one view that makes that visible.
- **Prefer `diff` against the existing shape.** The `+` and `-` lines are the change, the
  context lines show where it lands. Show the whole block instead when most of it is new, or
  when the diff markers would hide ownership or order.
- **Keep only what the change touches or depends on.** A file tree of every touched file is
  the diff summary in another font, see [Stop at what it does](#stop-at-what-it-does). Keep
  the calls, files, props, states and boundaries a reviewer needs and drop the rest.
- **Lead into each view with one short sentence**, never a heading. The sentence says what
  the view shows; the view shows it.
- **Text views go in the body, rendered views in a comment.** A fenced call tree or file
  tree reads the same in `git log` as on GitHub. Mermaid renders only on GitHub, and an HTML
  page or a screenshot not at all in `git log`, so those go in a
  [comment](#merge-danger-and-detail-go-in-a-pr-comment). Upload screenshots and pages with the
  `image-upload` skill.

````markdown
The shared cloud ran out of memory during ingest bursts, because every
cache miss in `get_device` inserted into the device cache however full
it was.

Now, skip the insert while the cache sits above `HIGH_WATER_MARK`. Mind
that misses past the mark go to DynamoDB every time until the cache
drains.

```diff
 get_device(id)
   if cache has id
     return cached
   device = dynamo.get(id)
-  cache.insert(id, device)
+  if cache.len() < HIGH_WATER_MARK
+    cache.insert(id, device)
   return device
```
````

The two prose paragraphs carry the problem, the change and the cost. The diff shows where
the guard sits, which would otherwise take a third paragraph.

## Merge danger and detail go in a PR comment

Every PR gets one reviewer comment, posted right after the PR is opened. It opens on the
[merge danger](#open-the-comment-on-merge-danger), and below that it carries material that
is worth keeping but does not belong in a commit message:

- how the approach changed mid-flight, and what a review round found,
- merge and conflict notes,
- deep rationale a reviewer needs now but posterity will not. The split is durability, not
  depth. The reason the change exists and the constraint that shaped it stay in the body
  however long they take to state. The survey of options, the benchmark that settled a
  choice, and the reply to a reviewer's objection go here,
- **evidence**: a before and after that shows the change works. A screenshot is the
  strongest when the change is visual and the environment can render it; upload it with the
  `image-upload` skill. Otherwise show execution, the exact test that failed before and
  passes now, or the command output that changed. Then what you ran it against, the numbers
  you cross-checked, and what is still unverified,
- **worked examples**, walkthroughs and sample payloads,
- **diagrams** too large for the body: state machines, cutovers, Mermaid, HTML pages and
  screenshots, and any `show-me` view past the one or two the body carries.

Misplaced depth is the problem, not depth. Never delete any of it, relocate it, and link it
from the description in one line only if a reader of the description would want it. This
applies to PRs you open too. Editing someone else's PR is an edit, not a rewrite, so their
voice, diagrams and tables survive the move intact.

A comment never becomes a commit message, so none of the commit-message constraints apply to
it. Do not hard-wrap it, and do not ration its length. Let GitHub reflow the prose, and give
a walkthrough or a table the room it needs.

The body says what the change does and, in a view or two, its shape. The comment says what
merging risks and shows the rest.

Keep that one comment current. When new commits change the diff, edit it in place rather
than posting another, so the merge danger a reviewer reads always describes the diff they
are about to merge.

```bash
gh api repos/<owner>/<repo>/issues/<number>/comments \
  --jq '.[] | select(.body | startswith("## Merge danger")) | .id'
gh api --method PATCH repos/<owner>/<repo>/issues/comments/<id> -F body=@<file>
```

### Open the comment on merge danger

A reviewer deciding whether to merge needs two answers before anything else: can this be
walked back, and what breaks if it is wrong. The comment answers both in its first lines,
under a `## Merge danger` heading, so the reviewer can weigh the risk without expanding
anything.

```markdown
## Merge danger

**Door:** two-way. Reverting the PR restores the old insert path, and nothing it writes
outlives the revert.

**Blast radius:** service. Every `get_device` caller in `ingest` sees cache misses past
`HIGH_WATER_MARK` go to DynamoDB, so read capacity on `devices` rises during bursts.
```

- **The door is one-way when a revert cannot undo the merge.** Dropped or rewritten stored
  data, a schema migration, a deleted or replaced cloud resource, a published release or API
  version that consumers pick up, a message sent to customers, a rotated credential. Name
  the step that makes it one-way, and what has to happen before merging if anything does:
  the backup, the deploy order, the consumer that must move first. Everything else is a
  two-way door, and the line says what a revert restores.
- **The blast radius is one word, then what it reaches.** The word sizes it: `none`,
  `local`, `service`, `cross-service`, `tenant`, `customer-facing`. The sentence after
  it names what a wrong merge would hit, as the code names it: the consumers, the
  environments, the tenants, the devices, the layout. Consider every path the change
  reaches, not only the one it was written for. Layout shift, a consumer of a changed
  contract, a mobile breakpoint and a cold cache are all blast radius.
- **Rate it from the diff, not from the intent.** A `cdk diff` that shows a replacement, a
  migration file, a changed response field settle the door and the radius. Read them out of
  the branch rather than guessing, and say so plainly when the door is one-way or the radius
  is wide. Inflating a two-way door into a scare is as wrong as hiding a one-way one.
- **It rates the risk; it does not replace the body.** A breaking change or a cost is still
  stated in the body, where `git log` keeps it. The merge danger is a judgement about this
  merge, true only until it lands, which is why it lives in the comment.
- **A trivial change still gets it.** A typo fix is two lines, `two-way` and `none`, and
  the reviewer learns that in a glance rather than by reading the diff to find out.

The idea comes from the `pr` skill in
[mattpocock/skills](https://github.com/mattpocock/skills/blob/main/skills/engineering/pr/SKILL.md).

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
- **One `<details>` per topic.** The evidence, a worked example and a state diagram
  are three things a reviewer reaches for separately. Three blocks with three summaries let
  them open one; a single block makes them scroll past the other two.
- **Put nothing outside the blocks but the merge danger.** It stays open because it is the
  reason the reviewer opened the comment. Any other sentence left outside a `<details>` is
  the part of the comment that was not worth collapsing, which means it belonged in the body.

````markdown
## Merge danger

**Door:** two-way. Writes land in both stores from this PR and reads stay on the old one,
so reverting this PR alone restores the previous behaviour and leaves no data stranded.

**Blast radius:** service. A dual-write failure fails the request in `ingest`, where it
used to succeed against the old store alone.

<details>
<summary>Expand for the cutover sequence and the backfill check</summary>

Reads stay on the old store until the backfill job reports 100%.

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

### Diagram what the body cannot carry

State machines, migrations, cutovers, ordering and fan-out rarely fit in a single
[`show-me` view](#show-the-shape-dont-narrate-it). When a change is state-heavy, a diagram
in the comment replaces a paragraph the reviewer has to hold in their head. An ASCII diagram
in a fenced block works everywhere. A Mermaid `sequenceDiagram` or `stateDiagram` suits a
flow with many actors, because GitHub renders it in a comment.

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

The rules for [body views](#show-the-shape-dont-narrate-it) hold here too. Beyond them,
annotate rather than decorate: an arrow without a label is a line, and a diagram that needs a
paragraph to interpret has failed, so redraw it smaller.

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
  ...", matching `git log` and every generated message around it. A refine pass never
  restores the capitals of the older history.
- **Keep the whole line under 72 characters**, the description after the prefix nearer 50.
  A title that needs more is usually two changes.
- **Say what changes and, when it fits in 72 characters, why.** `fix(api): reject empty
  device ids` gives the what. `fix(api): reject device ids that crashed sync` gives both,
  and the title becomes searchable by the symptom as well as by the fix. State what the
  change does now, not what it set out to do.
- **No filenames.** `fix(sync): handle empty device ids`, not `fix(sync): update devices.rs`.
  The diff already says where the change is. The title has to say what it does.
- On an existing PR, keep the current type and scope unless the diff shows they are wrong.

## Restraint

Act when a description is stale, stating a superseded approach, listing changes no longer
in the diff or omitting a major change now present, or when it breaks any rule above. When
it never says what problem the change solves, or cites no issue, find or file one as
[Cite the report behind it](#cite-the-report-behind-it) describes. When nothing settles
what the problem was, put that in the report rather than a guess in the body or an issue.

Reorder an accurate but hard-to-read description only when doing so surfaces something
buried.

When the diff is two unrelated changes, no single description can be honest about it. Write
the body around the one that dominates, state the other plainly rather than blending them,
and say in the report that the PR would read better split.

- **Verify every claim against the current diff**, and against the branch where the diff does
  not settle it. A body may name a default, a metric or an environment variable the diff only
  touches indirectly; read it out of the branch head rather than trusting the draft. Never
  state a change you cannot see.
- **Change the title, the body and the merge-danger comment only.** Never touch state, base branch, draft status, reviewers
  or labels. A body written to these rules makes a draft look finished, so a sweep is where
  a promotion slips in, and the review requests it sends cannot be taken back.
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
