---
name: pr-description
description: Write or refine a PR title, body and merge-danger comment so the body reads as the squash-merge commit message. Use when opening a PR, editing its body, or sweeping open PRs ("refine my PRs").
---

# PR description: write the commit message

On squash-merge the description becomes the commit message. Write it for someone who reaches
it from `git blame` in a year with no access to the review. They can see the diff. What they
cannot recover is why anyone touched this code, so a body that only summarises the diff adds
nothing.

A passage that would read oddly in `git log` belongs in the PR comment or nowhere. These
are the kernel's
[patch-submission conventions](https://www.kernel.org/doc/html/v4.17/process/submitting-patches.html#describe-your-changes)
applied to GitHub, with the PR comment as the part below the `---` line.

One problem per PR. A body that grows past a few short paragraphs usually carries two changes
rather than one hard one. Say the PR wants splitting rather than stretching the body.

Apply this skill to every PR you open or touch. Older merged history capitalises titles and
carries `@handle`s; follow the rules here, not that corpus.

## Modes

**Single PR** is the default: the one you just opened, or the one the user named. **Sweep**
is when the user asks to scan a set ("all open PRs authored by martinjlowm in
FactbirdHQ/nest"). Enumerate them, apply the rules to each, then draft the [report](#report).

```bash
gh pr list --repo <owner>/<repo> --state open --author <login> \
  --json number,title,url,body,headRefName
gh pr diff <number> --repo <owner>/<repo>
```

## The body

- **Describe only the end state.** A reader who never saw the PR evolve must come away with
  an accurate picture. No "Addressed feedback", "Round 2" or "Update:" sections; fold what
  those changes do into the part they belong to.
- **Order by importance:** the problem, then the change, then the detail.
- **Put every behavioural change at the top**, and say outright when the change breaks a
  caller, an API or a stored format. A breaking change the body only implies reaches a reader
  who was skimming.
- **State the user-visible impact.** A fix says what the bug did to someone: the crash, the
  wrong number, the rows that went missing. A bug caught in review still gets the sentence,
  written as the impact it would have had.
- **Write the change in the imperative**, the code as subject. "Refresh the token 60s before
  expiry", not "This PR makes the token refresh". See [How it sounds](#how-it-sounds) for
  the sentences around it.
- **The body addresses nobody.** No question, no offer, no request for input. It is the
  commit message, and `git log` cannot answer back.
- **Verification goes in the comment.** Cut what CI guarantees: tests, clippy, rustfmt,
  biome, typecheck. A named test that failed before and passes now is evidence and goes in
  the comment. The exception is a measured result that is the point of the change, written
  as a claim about the change.
- **Cut process noise:** rebases, conflict resolutions, resolved bot comments, branch
  merges. Keep a stacking note only if it changes how today's diff reads.
- **End the body with the disclosure your session's rules define**, such as a laptop
  session's `<sub>Made with ❤️ by Claude (Opus 5.5)</sub>`, a loop's `Assisted-by:` or the
  fleet's `Agent Session:` trailer, last in the trailer block. Keep it when you rewrite a
  body, and add it when you rewrite one a person wrote, since the text is now yours. No
  other session link or attribution.
- **Keep** issue references and screenshots. A reference the reader should follow goes inline
  as a full URL, `https://github.com/FactbirdHQ/nest/pull/20189`, not `#20189`.
- **A ticket reference is never the description.** `Closes #125` as the whole body moves the
  explanation into a system the reader may not be able to open.
- **Release notes stay empty.** Keep a template's `## Release note:` headings and leave every
  bullet blank. That section is customer copy someone else writes, and a filled line reads as
  decided and ships.

### Open on the problem

- **One or two sentences of problem, then the change in one sentence.** The problem is a fact
  about the code, not a story about the week.
- **Name the constraint that shaped the change** where the code would otherwise look wrong:
  the upstream bug, the format that cannot break, the limit. A rejected alternative earns a
  clause only when a future reader would otherwise "fix" the code back to it.
- **Link the source** when the change follows from a spec section, an upstream issue or a
  vendor doc.
- **Don't pre-argue.** The body states the reason; defending it against objections nobody has
  raised belongs in review.
- **Never invent the problem.** Take it from the linked issue, the branch's commits or the
  session. If none settles it, ask. A confident wrong reason misleads every later reader.

> Approving a manually-gated production deployment means approving blind: the gate names
> which projects will deploy, not what they will change.
>
> Run `cdk diff` before the approval gate and emit it as workflow annotations.

### Cite the issue behind it

Every PR references a GitHub issue for the problem it solves. A Zendesk ticket, incident,
alert or review comment is where the problem surfaced; it goes inline as a full URL beside the
issue, never in place of it.

- **Look first:** the prompt, the session, the branch's commits, then
  `gh issue list --repo <owner>/<repo> --state all --search "<symptom>"`.
- **No issue? File one** in the PR's repository before creating the PR. Title it with the
  problem, not the fix. The body says what is wrong, what it costs and where it shows, with
  the evidence a reader needs to believe it: the failing test and its output, the log line,
  the query and its result, a screenshot via `image-upload`. If the session does not settle
  the problem, ask rather than file a guess. Add no labels, assignees or project. Leave the
  body unwrapped, one line per paragraph: the 80-column wrap below exists for the commit
  message, and an issue never becomes one.
- **Set the issue Type** on every issue you file and on any cited issue that has none: `Task`
  by default, `Bug` for a fault in shipped behaviour, `Feature` for new functionality someone
  asked for. Leave a type someone set alone.
- **An existing issue without evidence** gets the evidence before the PR cites it. On the
  user's own issue, comment it. On anyone else's, draft the comment for the user to approve,
  and a headless session puts the evidence in the PR body instead. The issue body stays the
  author's.
- **Customer data stays in Zendesk.** An issue filed from a ticket links it and describes the
  problem in product terms, with no names, contact details or conversation.
- **Resolved issues go in trailers**, one `Closes <full URL>` line each, at the end of the
  body. An issue the PR only advances goes inline, since `Closes` would close it on merge. A
  prompt that prescribes its own trailer form wins.

```bash
gh issue create --repo <owner>/<repo> --title "<problem>" --body-file <file> --type Task
gh issue edit <number> --repo <owner>/<repo> --type Task
```

## How it sounds

Three registers, one per job:

- **What the change does:** imperative, the code as subject. "Reject device ids that crashed
  sync."
- **What was wrong:** past tense, whatever subject is true. "The shared cloud started running
  out of memory."
- **What you did, measured or do not know:** first person. "I ran `yarn cdk diff` on both
  stacks, and only the second showed a diff." This register lives mostly in the comment.

Four openers carry the paragraph order and keep colon splices out:

| Opener | Job |
| --- | --- |
| `Now,` | Turns from the problem to the change. |
| `Instead,` | Introduces the simpler alternative. |
| `Mind that` | Introduces the cost or caveat. |
| `Turns out` | Opens a corrected assumption. |

Contractions stay. Honest hedges ("presumably", "AFAIK", "I'm not sure if") stay; laundering
one into confidence is a defect.

## Length and shape

Reviewer time is the cost of every line. Aim for the shortest body that lets a reader review
the diff and, a year later, see why it exists.

- **A typo or mechanical fix:** a title and no body.
- **An ordinary fix or feature:** two to five sentences of prose.
- **Past a short paragraph, or more than one behavioural change:** a one-line summary of
  what changed and why, the changes one per bullet, then the detail and anything out of scope
  under headings, then the trailers.
- **Wrap the body at 80 columns.** Markdown joins the lines, so the width only serves the
  raw text under `git log` and in the editor. Leave fenced blocks, tables and links
  unwrapped. An issue body is never a commit message and stays unwrapped.
- **Answer "what" once.** Do not walk through every case or call site that follows; a reader
  who needs that reads the diff.
- **A summary of the diff is not a description.** Listing touched files and renamed
  functions crowds out the problem, the one thing the reader cannot derive.
- **Mechanism that leaves no trace in behaviour** (how an interpreter is pinned, why an
  import list is short) is code-comment material.
- **State the assumption, not the arithmetic.** When the change narrows scope, the
  load-bearing sentence is the invariant that makes the narrower scope sufficient.
- **Every change states its cost.** What was traded for the gain: the memory the batch
  holds, the staleness the cache allows, the duplicate effect of a retry. `Mind that`
  carries it.
- **Name things as the code names them**, so a reader can grep for them. Dates are absolute,
  `2026-07-28`, never "last month".

| Instead of | Write |
| --- | --- |
| Fixed a race condition. | `flush()` awaited the write it just queued, so two concurrent callers could interleave. It now holds the lock across queue-and-write. |
| Various performance improvements. | Dropped the per-row `SELECT` in `sync_devices`, one batched query instead of N. 4.2s to 180ms on 5k devices. |
| Added `[Required]` to `ReservationRequestModel`. | Reservations were accepted without a phone number, crashing the dispatch job. `PhoneNumber` is now required on `/reservations`; that breaks existing callers, so the endpoint is versioned to 2.0. |

### Show the shape

Prose is bad at shape: which call runs before which, which file took over which
responsibility, which field a contract gained. Draw it with the views in the `show-me` skill
(`~/.claude/skills/show-me/SKILL.md`): pseudocode, a call tree, a file tree, a type, a table.

- **A view replaces a paragraph**, never sits beside one. The problem and change sentences
  still come first.
- **One view, two at most**, and only where the change has a shape. Prefer `diff` against
  the existing shape. Keep only what the change touches.
- **Lead in with one sentence**, not a heading.
- **Text views go in the body; Mermaid, HTML and screenshots go in the comment**, since they
  do not render in `git log`.

````markdown
The shared cloud ran out of memory during ingest bursts, because every
cache miss in `get_device` inserted into the device cache however full it
was.

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

## The companion comment

Opening a PR, post one comment right after it. It opens on the merge danger and carries what
is worth keeping for the reviewer but not for `git log`:

- how the approach changed and what review found, merge and conflict notes,
- rationale a reviewer needs now and posterity will not: the survey of options, the benchmark
  that settled a choice,
- **evidence**: a before and after that shows the change works. A screenshot (via
  `image-upload`) when the change is visual, otherwise the test that failed before and passes
  now, or the command output that changed. Then what you ran it against and what is still
  unverified,
- worked examples, sample payloads, and diagrams too large for the body.

When you open a PR, move such material out of the body into this comment rather than deleting
it. Wrap the comment at 80 columns like the body. The comment ends with the
same disclosure as the body, or with the session footer when the instructions in context
define one.

```bash
gh pr comment <number> --repo <owner>/<repo> --body-file <file>
```

### Merge danger

The comment opens with two answers under a `## Merge danger` heading: can this be walked back,
and what breaks if it is wrong.

```markdown
## Merge danger

**Door:** two-way. Reverting the PR restores the old insert path, and
nothing it writes outlives the revert.

**Blast radius:** service. Every `get_device` caller in `ingest` sees cache
misses past `HIGH_WATER_MARK` go to DynamoDB, so read capacity on
`devices` rises during bursts.
```

- **The door is one-way when a revert cannot undo the merge:** dropped or rewritten data, a
  schema migration, a replaced cloud resource, a published release or API version, a message
  sent to customers, a rotated credential. Name the step that makes it one-way and what must
  happen before merging. Otherwise it is two-way, and the line says what a revert restores.
- **The blast radius is one word, then what it reaches:** `none`, `local`, `service`,
  `cross-service`, `tenant`, `customer-facing`, followed by the consumers, environments,
  tenants or layout a wrong merge would hit, named as the code names them.
- **Rate it from the diff, not the intent.** A `cdk diff` replacement, a migration file or a
  changed response field settles it. Inflating a two-way door is as wrong as hiding a one-way
  one.
- **It does not replace the body.** A breaking change or a cost is still stated in the body,
  where `git log` keeps it.

### Collapse the rest

Everything after the merge danger sits in `<details>` blocks, one per topic, so a reviewer
expands only what they want. Anything worth leaving outside a block belonged in the body.

- **The `<summary>` says what expanding gives:** `Expand for the cutover sequence and the
  rollback path`, never `Details`.
- **Leave a blank line after `</summary>`**, or GitHub renders the markdown inside as text.
- **Correct the content, not the history of the prose.** No "an earlier version of this
  section was wrong". An in-flight strikethrough that says something true about the current
  diff stays.
- **Diagram what the body cannot carry.** State machines, cutovers and fan-out suit a
  ` ```mermaid ` block here. Label arrows with why, mark what this PR changes, keep it small.

````markdown
<details>
<summary>Expand for the cutover sequence and the rollback path</summary>

```
before            during (this PR)            after
app               app                         app
 +-write-> old     +-write-> old  <- kept      +-write-> new
 +-read--> old     +-write-> new     for       +-read--> new
                   +-read--> old     rollback
```

Reads stay on the old store until the backfill job reports 100%.

</details>
````

## Editing an open PR

- **Relocation into the comment happens only when opening.** On an existing PR, material that
  no longer belongs in the body is cut; the edit history keeps it.
- **Never add a companion comment** to a PR that has none.
- **Edit the companion comment only when it is now wrong**, such as a merge danger the new
  diff no longer matches, in place:

```bash
gh api repos/<owner>/<repo>/issues/<number>/comments \
  --jq '.[] | select(.body | startswith("## Merge danger")) | .id'
gh api --method PATCH repos/<owner>/<repo>/issues/comments/<id> -F body=@<file>
```

- **Refresh the body** when a push changed what the PR does. Editing someone else's PR is an
  edit, not a rewrite: their voice, diagrams and tables survive.

## Titles

`<type>(<scope>): <description>`

- `type` is `feat`, `fix`, `chore` or `docs`. `scope` is the affected project directory,
  `chore(ui-app,ui-auth): ...` for two, `chore(*): ...` for many.
- **Imperative, lowercase, no trailing period.** `fix(api): reject empty device ids`. It
  completes "this change will ...".
- **One line under 72 characters**, the description nearer 50. A title that needs more is
  usually two changes.
- **Say what changes and, when it fits, why.** `fix(api): reject device ids that crashed sync`
  is searchable by the symptom too.
- **No filenames.** The diff says where; the title says what.
- On an existing PR, keep the type and scope unless the diff shows they are wrong.

## Restraint

Act when a description is stale (a superseded approach, changes no longer in the diff, a
major change missing) or breaks a rule above. When it never says what problem it solves or
cites no issue, find or file one. When nothing settles the problem, say so in the report
rather than guessing. Reorder an accurate body only when that surfaces something buried.

When the diff is two unrelated changes, write the body around the one that dominates, state
the other plainly, and say in the report that the PR would read better split.

- **Verify every claim against the current diff**, and against the branch head where the
  diff does not settle it. Never state a change you cannot see.
- **Touch the title, the body and the merge-danger comment only.** Never state, base branch,
  reviewers or labels.
- When unsure, leave the PR alone and say so in the report.

```bash
gh pr edit <number> --repo <owner>/<repo> --title <title> --body-file <file>
```

## Report

Sweeps only. Draft the report for the Slack channel the user named (`#pr-refinement` for the
nest sweep) with `slack_send_message_draft` or as text in the session. The user sends it;
you never post it. A headless session puts it in its final message instead.

- one line per changed PR: number, link, and why it was stale,
- the count left unchanged.

Draft nothing when no PR needed changing; say so in the session.
