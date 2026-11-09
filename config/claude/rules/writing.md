# Writing

## Run `unslop` over everything a person reads

Commit messages, PR and issue titles and bodies, comments and replies, Slack drafts,
documentation, the prose in code comments, and your final message. Run it before handing the
text over and again after any substantial rewrite. These six bind whether or not the skill
is open:

- No em dashes, and no parentheses or en dash in their place. End the sentence or use a comma.
- A colon introduces a list or an example, never a second clause.
- No opener that agrees before it says anything: "You're right", "Good catch".
- Active voice with the actor named: "the compiler validates queries".
- Sentence-case headings and no decorative emoji.
- A concrete noun in every claim. A sentence that would fit another project unchanged says
  nothing about this one.

## Instructions an agent follows

A prompt, agent file, skill or subagent brief reaches a reader with none of your context.

- Write one instruction per sentence, in the imperative, at most 20 words.
- Keep a sentence that describes to at most 25 words, and a paragraph to one topic.
- Put the condition first: "If the PR is a draft, skip it."
- Repeat the noun where "it", "this" or "they" could mean two things.
- Write "must" for an obligation, "can" for a possibility and "if" for a condition.
  "Should" and "may" read as either.
- Call one thing by one name in every file that mentions it.

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
