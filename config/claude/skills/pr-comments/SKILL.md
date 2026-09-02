---
name: pr-comments
description: Address pull request review comments, then reply, resolve, or report depending on who wrote them. Own comments (martinjlowm) get a reply linking the fix and the thread resolved; bot reviews get the same reply and stay open; a colleague's comments get the fix and no reply, rolled into a comment-by-comment summary posted to #pr-reviews in Slack. Use when asked to "resolve PR comments", "address the review", "handle review feedback", or "go through the comments on PR #123".
---

# PR comments: fix every thread, write back to nobody but yourself and the bots

Every thread gets the fix. Who hears about it depends on who opened it. A colleague reviewing
this PR wants Martin to answer them, not a machine, so their thread gets the change and
silence, and the answer they get is a human one, later, from him. A bot has nobody to talk to
and the reply is the only record tying its finding to a commit, so it gets one.

```
thread author?
 │
 ├─ martinjlowm ──> fix ──> reply (what + permalink) ──> resolve thread
 │                                                       ▲
 │                                          only after the fix is pushed
 │
 ├─ any bot ─────> fix ──> reply (what + permalink) ──> leave unresolved
 │
 └─ any human ───> fix ──> no reply, no draft, no offer to write one
                    │
                    └──> entry in the #pr-reviews summary, for Martin to answer
```

All three paths run in one pass. A PR usually has more than one of them.

## When to use

The user asks to resolve, address, or handle PR comments or a review, with or without a PR
number. Not for writing PR bodies, which is `pr-description`, or reviewing someone else's
code, which is `/review`.

## Inputs

1. PR, optional. A number, a URL, or nothing. With nothing, use the current branch's PR.
2. Scope, optional. Specific threads or reviewers. Default is every unresolved thread.

## Collect the threads

Review threads, the inline resolvable ones, come from GraphQL. The REST comments endpoint
exposes neither thread IDs nor resolution state, so it cannot drive this skill:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      headRefOid
      reviewThreads(first:100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first:50) { nodes { databaseId author { login } body } }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<number>
```

Top-level PR comments and review summary bodies are a separate stream with **no resolve
action**:

```bash
gh pr view <number> --json number,title,url,headRefOid,comments,reviews
```

- Skip threads where `isResolved` is true.
- Keep `isOutdated` threads in scope. The code moved, the point may not have.
- The deciding author is `comments.nodes[0].author.login`.
- A login ending in `[bot]` is a bot: `claude[bot]`, `martinjlowm-s-botler[bot]`,
  `dependabot[bot]`, `coderabbitai[bot]`, `github-actions[bot]`, and the rest. Reply to them,
  never resolve them, leave them out of the Slack summary. Their thread holds its own record.
- Every other login is a colleague. Fix, stay silent, summarise.

## Address each comment

Every thread ends in one of four outcomes. Pick one. Ignoring a comment is not an outcome,
and on a colleague's thread the outcome lands in the diff and the summary rather than in a
reply.

| Outcome | Action |
| --- | --- |
| Agree | Make the change. |
| Already handled | Point at the commit or line that handles it. |
| Disagree | Change nothing. Give the reason, in the reply on your own or a bot thread, in the summary entry on a colleague's. |
| Needs the user | Leave open, decide nothing on their behalf, list as pending. |

Verify the way the project expects, with its build, tests, and lint, then commit and push
**before** replying or summarising. A line you link must point at pushed code. One commit per
coherent group of feedback, not one per comment.

## Write the reply like a description, not a receipt

This section governs the threads you post on, your own and the bots'. A colleague's thread
gets no reply at all, so skip to the report for those.

The same rules as `pr-description`, at one-comment scale: describe the end state, name the
thing, cut the throat-clearing. Two lines is usually the whole reply.

**Every claim is verified against the diff.** Never state a change you cannot see in
`git diff`. This is the one rule that makes resolving a thread safe.

| Instead of | Write |
| --- | --- |
| Fixed! | `flush()` now holds the lock across queue-and-write. |
| Good catch, addressed in the latest commit. | Dropped the per-row `SELECT` in `sync_devices`, now one batched query. |
| Refactored as suggested. | Split `handler.rs` into `parse.rs` and `dispatch.rs`. No behavioural change. |
| I don't think that's an issue. | Keeping the retry. The upstream 429 needs the backoff. Comment added at `http.rs:42`. |
| Done, see line 88. | Done: <permalink> |

Cut what the thread already knows. No restating the reviewer's comment, no "thanks for the
review", no "let me know if you'd like anything else".

### Never mention a person

**No reply or comment you post names a person.** The thread already notifies everyone on it,
so a `@handle` adds nothing but a second notification, and it pulls anyone else you name into
a conversation they were not part of. This holds for inline replies, top-level comments,
review summaries, and any body you edit.

- No "@reviewer good catch", no "as @someone suggested", no addressing the reviewer by name.
  Open on what changed.
- Never name a third party to route the thread to them. If a thread needs someone else, say
  what is undecided and leave it in the report; the user pulls them in.
- A handle that is part of the change itself, a CODEOWNERS line or a config value, goes in a
  code span or a fenced block, never in running prose.
- Before posting, grep the body: every `@` must sit inside a code span or be gone.

```bash
grep -n "@[A-Za-z0-9]" <file>
```

### Link the location

Build the link from the pushed head SHA. A blob permalink survives later pushes; a branch
line number does not.

```bash
gh pr view <number> --json headRefOid --jq .headRefOid
# https://github.com/<owner>/<repo>/blob/<headRefOid>/<path>#L<line>
# range: ...#L<start>-L<end>
```

Link only when code changed and the change is somewhere the thread does not already sit. A
one-line edit on the commented line needs no link.

### Post it on the thread

Check the author one more time before this call. The body is posted only when the thread's
first comment comes from `martinjlowm` or a `[bot]` login, and there is no version of this
step that runs on a colleague's thread: not a shorter reply, not a reply the user approves in
the session first, not an offer to write one. Post nothing and say nothing about posting.

Reply to the thread's **first** comment `databaseId`. A new top-level comment loses the code
context and cannot be resolved:

```bash
gh api --method POST \
  repos/<owner>/<repo>/pulls/<number>/comments/<databaseId>/replies \
  -f body='<reply>'
```

## Resolve, own threads only

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
}' -F threadId=<thread id>
```

### Restraint

Resolve only when **all** of these hold:

- the thread's first comment author is `martinjlowm`,
- the fix is pushed (or the outcome is a reasoned decline),
- the reply is posted.

A bot thread stays open even though you replied to it. The reply is the record; closing the
thread is the user's reading of whether the finding is dealt with. Never resolve a colleague's
thread, however obvious the fix. Never resolve a thread left pending on the user. Never
resolve silently. When genuinely unsure, leave the thread open and say so in the session.

## Report

One Slack message per PR, to **#pr-reviews**, covering the threads nobody has answered: the
ones a colleague opened. The user's own threads and the bot threads carry their reply on
GitHub and stay out of it. This message is what the user reads before writing back to the
reviewer, so it says what the reviewer asked and what the code now does, comment by comment,
in thread order:

```
*<repo>#<number>*: <PR title>
<PR url>

*@<reviewer>* `<path>:<line>`
> <the comment, trimmed to its point>
✅ <what changed> · <permalink>

*@<reviewer>* `<path>:<line>`
> <comment>
💬 <why nothing changed>

*@<reviewer>* general comment
> <comment>
⏳ Needs Martin: <what is undecided>

<n> addressed · <n> declined · <n> pending
```

The `*@<reviewer>*` heading is plain text, a label so the user can tell the entries apart.
Never build it as a real Slack mention (`<@U…>`), and never mention anyone in the summary
body.

`✅` addressed · `💬` declined with reasoning · `⏳` pending. Two lines per entry. The detail
lives on the threads, and the summary exists to be skimmed.

Post with `mcp__claude_ai_Slack__slack_send_message` to `#pr-reviews`. Resolve the channel
with `slack_search_channels` if the name does not take.

- Post nothing when no colleague opened a thread. Note the quiet run in the session.
- If Slack is unreachable, print the summary in the session and say the post could not be
  made.

## Notes

- Top-level PR comments and review summaries cannot be resolved. Route them by author like
  any other thread: `gh pr comment` for the user's own and for a bot, the Slack summary for a
  colleague's.
- A comment asking for work outside the PR's scope gets a follow-up note and no wider diff.
  Say so in the reply, or in the summary entry when a colleague raised it.
- Do not offer to reply to a colleague, in the session or anywhere else. Their unanswered
  thread is the finished state, so it is not an open item and does not belong in a list of
  what is left to do.
- Everything `pr-description` says about not naming people applies to comments too, and to
  any PR body this pass makes you edit.
- Never change the PR's draft or ready status. Addressing every thread is not the same as the
  work being handed over; a draft that now has all its feedback resolved is still a draft, and
  `gh pr ready` stays the user's call.
- If the review changed what the PR does, update the body with `pr-description`. Fold the
  change into the section it belongs to; a commit message has no "addressed feedback"
  section.
