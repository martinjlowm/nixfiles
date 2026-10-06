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

## Claim only what you checked

Never claim a check you did not run, a test you did not execute, a file you did not read or
a deployment you did not verify. Where a reader would assume you verified something and you
did not, say so. A suite that could only partly run has not passed.

## Code comments

A comment states what the code does and what makes it correct, in the present tense, for a
reader who never saw the diff that introduced it.

- **Ask where the reader looks for it.** What only parses next to the diff belongs in the
  commit message or PR body: what the code did before, rollout order, temporary state,
  ticket numbers, the incident behind it. In the code it outlives the world it describes.
- **Earn the comment.** Write one for a design fact bound to that site that neither the code
  nor its names make obvious. A comment that narrates the line below it goes, and a
  paragraph above a short function usually means the function needs a better name.
- **One fact, one site.** Put it where the reader makes the decision it governs and leave
  the other sites bare, so a change to the rule has one place to update.
- **One sentence per fact.** A safety claim states the property that holds it up, once, and
  claims the general property rather than the arrangement that satisfies it today.

```ts
// The push endpoint rotates over a subscription's life, so it cannot key the
// table. (userPool#userSub, deviceId) stays fixed, so a rotation overwrites the
// device's own row instead of orphaning it.
```

## Diagrams

When a shape says more than a paragraph, such as a call order, a file layout or a before and
after, draw it with the views in the `show-me` skill (`~/.claude/skills/show-me/SKILL.md`).
The skill sets `disable-model-invocation`, so read the file rather than invoking it, and pick
the smallest view that makes the point.

## Documentation: four modes, kept apart

Documentation committed to a repository serves exactly one reader need per page.

- **Tutorial.** Walks a beginner down one path that works. Explicit, no choices, no
  explanations.
- **How-to guide.** Gets a competent reader to a stated goal. Branches on real conditions and
  teaches nothing.
- **Reference.** Describes the machinery, structured to mirror it. Austere, never
  instructive. Every option, attribute and default is read out of the code before it is
  written down, and a name that is defined but never wired up is documented as such.
- **Explanation.** Why the code is shaped this way, what was rejected, the history. Never
  instructs or catalogues.

Diagnose a page by the need it serves, not its length, and move intruding material to the
page that owns it rather than deleting it. Name sections after the four modes, but do not
cite or link the framework behind them.
