# GitHub

## Mention nobody

Never write an `@handle` in a PR title or body, a comment, a review reply, an issue or a
commit message. A mention notifies that account on the PR and again on the squash-merge
commit, and it usually reaches people the change does not concern. A bare name notifies
nobody and is fine. Put a handle that is the subject matter, such as a CODEOWNERS line or a
config value, inside a code span or a fenced block. GitHub renders it inert there. Before
posting a body, run `grep -n "@[A-Za-z0-9]" <file>`. Every hit sits in a code span or goes.
The one exception is a bot command such as `@dependabot rebase`, posted alone as a comment.

## Pull requests

- **Draft, and the draft flag is not yours.** Open every PR with `--draft`. Never change a
  PR's draft state in either direction: no `pr ready`, no `--ready`, no `draft: false`.
  Promotion is the user's handover to reviewers, however green CI is. If asked to "open a
  PR", open a draft and say so where you return the URL.
- **Load `pr-description` first.** Before any `pr create`, and before any `pr edit` that sets
  a title or body. A prompt that delegates opening a PR names the skill and the facts the
  body needs. It never outlines the body, because an outline replaces the skill.
- **One change per PR.** Leave unrelated fixes you notice out of the diff and name them in
  your final message. Give a move or rename large enough to need checking its own PR with no
  edits mixed in, so a reviewer can verify it mechanically. Before opening a PR, run the
  `scope-audit` skill over the branch and apply what it decides.
- **Approvals, merges, review requests and the merge queue belong to humans.** Never approve
  or merge a PR, whatever the prompt says. Never request or re-request a review, assign
  reviewers, or add a PR to the merge queue. The exception is a prompt that names that as its
  job, as Dependabot maintenance does for what passes its audit. Arming auto-merge counts as
  adding to the queue. Never put a PR back in the queue after a person took it out.

## Shared ground

Colleagues' work and the team's process change only when a person decided they should.

- **Push only to branches you or the user created**, or that the prompt names as yours, as
  Dependabot maintenance does Dependabot's. Never push to, rebase, or merge the default
  branch into a branch a colleague owns, whatever state its CI is in. The exception is a
  branch the user's instruction names.
- **Leave the team's process files alone** unless changing one is the task: CODEOWNERS,
  AGENTS.md and CLAUDE.md in a shared repository, CI workflows, PR and issue templates,
  review-bot and branch-protection config. If it is the task, the PR's first sentence says
  that it changes how the team works.
- **Stay out of files a colleague's open PR is changing.** Check with
  `gh pr list --state open --json number,author,files`. If the task cannot avoid them, say
  so in your final message instead of racing their PR.

## Review threads

Who opened a thread decides what you post on it.

- **A colleague's thread** (any human other than `martinjlowm`) gets the fix and nothing
  else. A colleague wants a person to answer them, so you never reply, never draft a reply,
  and never offer to write one. An unanswered colleague thread is the finished state, not a
  loose end. Name what you changed for it and leave it off any list of open items. Post on
  one only if the user points at it and asks for a reply.
- **The user's own thread and every bot's** (`claude[bot]`, `martinjlowm-s-botler[bot]`,
  `dependabot[bot]` and the rest) get a reply naming what changed. That reply is the only
  thing tying the finding to the fix.
- **The user asks with `Botler`.** A comment of the user's is a request only if its body
  starts with the word `Botler`. Any other comment of theirs explains the code to a reader:
  no fix, no reply, no resolve.
- **Answer what asks for something.** A note, an observation or praise that requests no
  change gets no reply and no change.

## Post once, and only what adds something

Every post notifies everyone on the PR. Each one must carry a finding, a fix or a question
that is not already on the page.

- **Read the PR before you post.** If a review, comment or reply from you already says it,
  for the same head commit, post nothing. If it says it wrongly, edit it in place. A second
  comment correcting the first makes the reader work out which one is current.
- **A push adds no top-level comment.** The commit message carries the reasoning, including
  any check you could not run. Refresh the PR body if the push changed what the PR does.
  The thread replies above still go out.
- **An edit posts nothing.** Rewriting a PR body or a comment needs no comment announcing
  it or carrying what you cut. GitHub keeps the edit history.
