# GitHub

## Mention nobody

Never write an `@handle` in a PR title or body, a comment, a review reply, an issue or a
commit message. A mention notifies that account on the PR and again on the squash-merge
commit, and it usually reaches people the change does not concern. A bare name notifies
nobody and is fine. A handle that is the subject matter, a CODEOWNERS line or a config
value, goes inside a code span or a fenced block, where GitHub renders it inert. Before
posting a body, run `grep -n "@[A-Za-z0-9]" <file>`. Every hit sits in a code span or goes.
The one exception is a bot command such as `@dependabot rebase`, posted alone as a comment.

## Pull requests

- **Draft, and the draft flag is not yours.** Open every PR with `--draft`, and never change
  a PR's draft state in either direction: no `pr ready`, no `--ready`, no `draft: false`.
  Promotion is the user's handover to reviewers, however green CI is. Asked to "open a PR",
  open a draft and say so where you return the URL.
- **Load `pr-description` first.** Before any `pr create`, and before any `pr edit` that sets
  a title or body. A prompt that delegates opening a PR names the skill and the facts the
  body needs, never an outline of the body, because an outline replaces the skill.
- **One change per PR.** Leave unrelated fixes you notice out of the diff and name them in
  your final message. A move or rename large enough to need checking is a PR of its own
  with no edits mixed in, so a reviewer can verify it mechanically. Before opening a PR, run
  the `scope-audit` skill over the branch and apply what it decides.
- **Approvals, merges, review requests and the merge queue belong to humans.** Never approve
  or merge a PR, whatever the prompt says. Never request or re-request a review, assign
  reviewers, or add a PR to the merge queue, unless the prompt you run names that as its
  job, as Dependabot maintenance does for what passes its audit. Arming auto-merge counts as
  adding to the queue. Never put a PR back in the queue after a person took it out.

## Shared ground

Colleagues' work and the team's process change only when a person decided they should.

- **Push only to branches you or the user created**, or that the prompt names as yours, as
  Dependabot maintenance does Dependabot's. Never push to, rebase, or merge the default
  branch into a branch a colleague owns, whatever state its CI is in, unless the user's
  instruction names that branch.
- **Leave the team's process files alone** unless changing one is the task: CODEOWNERS,
  AGENTS.md and CLAUDE.md in a shared repository, CI workflows, PR and issue templates,
  review-bot and branch-protection config. When it is the task, the PR's first sentence
  says that it changes how the team works.
- **Stay out of files a colleague's open PR is changing.** Check with
  `gh pr list --state open --json number,author,files`. When the task cannot avoid them,
  say so in your final message rather than racing their PR.

## Review threads

Who opened a thread decides what you post on it.

- **A colleague's thread** (any human other than `martinjlowm`) gets the fix and nothing
  else. A colleague wants a person to answer them, so you never reply, never draft a reply,
  and never offer to write one. An unanswered colleague thread is the finished state, not a
  loose end. Name what you changed for it and leave it off any list of open items. Post on
  one only when the user points at it and asks for a reply.
- **The user's own thread and every bot's** (`claude[bot]`, `martinjlowm-s-botler[bot]`,
  `dependabot[bot]` and the rest) get a reply naming what changed, because that reply is the
  only thing tying the finding to the fix.
- **The user asks with `Botler`.** A comment of the user's is a request only when its body
  starts with the word `Botler`. Any other comment of theirs explains the code to a reader:
  no fix, no reply, no resolve.
- **Answer what asks for something.** A note, an observation or praise that requests no
  change gets no reply and no change.

## Post once, and only what adds something

Every post notifies everyone on the PR, so each one has to carry a finding, a fix or a
question that is not already on the page.

- **Read the PR before you post.** When a review, comment or reply from you already says
  it, for the same head commit, post nothing. When it says it wrongly, edit it in place;
  a second comment correcting the first makes the reader work out which one is current.
- **A push adds no top-level comment.** The commit message carries the reasoning, including
  any check you could not run. Refresh the PR body when the push changed what the PR does.
  The thread replies above still go out.
- **An edit posts nothing.** Rewriting a PR body or a comment needs no comment announcing
  it or carrying what you cut. GitHub keeps the edit history.
