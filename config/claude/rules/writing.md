# Writing

## Style

One style governs everything you write to an agent or a person. It follows ASD-STE100,
Simplified Technical English, the aerospace standard built to keep one sentence from reading
two ways. It applies to:

- Commit messages, PR and issue titles and bodies, comments and replies, Slack drafts.
- Documentation and the prose in code comments.
- A skill, agent file or prompt.
- Every message you send the user.

Run the `unslop` skill for tone. Run the `asd-ste100` skill for a full structural pass. Do
both before sending text, and again after a substantial rewrite. These bind whether or not
either skill is open:

- Write one instruction, fact or claim per sentence, at most 20 words. A sentence that
  describes something runs to at most 25 words. A paragraph holds one topic.
- State an instruction in the imperative. Put a condition first: "If the PR is a draft, skip
  it."
- Use a list, not a prose run, for three or more items or steps.
- No semicolon. Split into two sentences instead.
- No phrasal verb: "start" not "kick off", "contact" not "reach out", "read" not "dive into".
- No noun cluster past three words stacked: "fuel pump valve" is fine, "high pressure fuel
  pump inlet valve" is not. Split it with "of" or a clause.
- No ellipsis. Keep the subject, verb and article, even where the sentence reads longer for
  it.
- Keep a hedge: "may have failed" is not "failed".
- Repeat the noun where "it", "this" or "they" could mean two things.
- Write "must" for an obligation, "can" for a possibility and "if" for a condition.
  "Should" and "may" read as either.
- Call one thing by one name in every file that mentions it.
- No em dashes, and no parentheses or en dash in their place. End the sentence or use a comma.
- A colon introduces a list or an example, never a second clause.
- No opener that agrees before it says anything: "You're right", "Good catch".
- Active voice with the actor named: "the compiler validates queries".
- Sentence-case headings and no decorative emoji.
- A concrete noun in every claim. A sentence that would fit another project unchanged says
  nothing about this one.

A code span, a quote or a parenthesis counts as one word.

## Claim only what you checked

Claim only checks you ran, tests you executed, files you read and deployments you verified.
If a reader would assume you verified something you did not, say so. A suite that could only
partly run has not passed.

## Code comments

A comment states what the code does and what makes it correct. Write it in the present
tense, for a reader who never saw the diff that introduced it.

- **Name it first.** Put every fact a name, type or assertion can hold into the code. Name a
  value with full nouns and the unit or qualifier last (`heartbeat_age_ms`, `latency_ms_max`).
  Name a function by its verb. Extract a labelled step into a function, and write an
  invariant as an assertion. A comment holds only what is left.
- **Ask where the reader looks for it.** Put what only parses next to the diff in the commit
  message or PR body. That covers what the code did before, rollout order, temporary state,
  ticket numbers and the incident behind it. In the code it outlives the world it describes.
- **Earn the comment.** Write one for a design fact bound to that site that neither the code
  nor its names make obvious. Delete a comment that narrates the line below it. A paragraph
  above a short function usually means the function needs a better name.
- **One fact, one site.** Put it where the reader makes the decision it governs. Leave the
  other sites bare, so a change to the rule has one place to update.
- **One sentence per fact.** A safety claim states the property that holds it up, once. It
  claims the general property, not the arrangement that satisfies it today.

```ts
// The push endpoint rotates over a subscription's life, so it cannot key the
// table. (userPool#userSub, deviceId) stays fixed, so a rotation overwrites the
// device's own row instead of orphaning it.
```

Before committing code that adds comments, run the `comment-audit` skill over the diff and
apply what it decides.

## Diagrams

If a shape says more than a paragraph, draw it with the views in the `show-me` skill
(`~/.claude/skills/show-me/SKILL.md`). Such shapes include a call order, a file layout or a
before and after. The skill sets `disable-model-invocation`, so read the file instead of
invoking it. Pick the smallest view that makes the point.

## Documentation: four modes, kept apart

Documentation committed to a repository serves exactly one reader need per page.

- **Tutorial.** Walks a beginner down one path that works. Explicit, no choices, no
  explanations.
- **How-to guide.** Gets a competent reader to a stated goal. Branches on real conditions and
  teaches nothing.
- **Reference.** Describes the machinery, structured to mirror it. Austere, never
  instructive. Read every option, attribute and default out of the code before writing it
  down. Document a name that is defined but never wired up as such.
- **Explanation.** Why the code is shaped this way, what was rejected, the history. Never
  instructs or catalogues.

Diagnose a page by the need it serves, not its length. Move intruding material to the page
that owns it instead of deleting it. Name sections after the four modes, but do not cite or
link the framework behind them.
