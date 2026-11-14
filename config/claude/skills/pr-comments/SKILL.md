---
name: pr-comments
description: Address the review threads on a PR, then reply, resolve or summarise by who opened each. Use when asked to "resolve PR comments", "address the review" or "handle review feedback".
---

# PR comments: fix every thread, then route by author

The "Review threads" rule in the GitHub rules decides what is posted. This skill adds the
mechanics, when to resolve, and the summary the user reads before answering colleagues.

```
thread author?
 |
 +- the user, `Botler ...` ---> fix -> reply (what + permalink) -> resolve, after the push
 |
 +- the user, anything else --> nothing: no fix, no reply, no resolve
 |
 +- any bot ------------------> fix -> reply (what + permalink) -> leave open
 |
 +- colleague ----------------> fix -> no reply -> entry in the summary
```

"The user" is `martinjlowm`. In the fleet you post as `martinjlowm-s-botler[bot]`, so your
own earlier replies carry that login and the user's threads still carry `martinjlowm`.

Match the `Botler` prefix literally at the start of the body. It applies to a thread the
user opens, a reply they add to any thread, a review body and a top-level comment. Any other
comment of theirs is context for the threads you act on, never work of its own. A bot's or a
colleague's comment needs no prefix.

A top-level `Botler` comment on a PR is not yours to act on. The fleet's Botler routine
answers it by editing the comment, so acting on it here does the work twice. A `Botler`
comment inside a review thread reaches no such routine, so it is review feedback and lands
here.

## When to use

Not for writing PR bodies (`pr-description`) or reviewing someone else's code.

Inputs: a PR number or URL, or the current branch's PR; optionally specific threads or
reviewers. Default is every unresolved thread.

## Collect the threads

Inline threads come from GraphQL, because the REST comments endpoint exposes neither thread
ids nor resolution state.

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      headRefOid
      reviewThreads(first:100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first:50) { nodes { databaseId author { login } body createdAt } }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F pr=<number>
```

Top-level comments and review summary bodies have no resolve action. Read them for findings
and answer each in the inline thread that carries it:

```bash
gh pr view <number> --json number,title,url,headRefOid,comments,reviews
```

- Skip resolved threads. Keep outdated ones; the code moved, the point may not have.
- The deciding author is `comments.nodes[0].author.login`. A login ending in `[bot]` is a
  bot; any other login except the user's is a colleague.
- **Skip the user's thread unless it asks.** If no comment of theirs in it starts with
  `Botler`, leave the thread exactly as it is, resolution state included. Keep it out of the
  report.
- **Skip a thread you already answered**: its last comment is your own reply and no reviewer
  comment came after it. Re-running the skill on the same PR posts nothing new there.

## Decide each thread

Every thread ends in one of five outcomes.

| Outcome | Action |
| --- | --- |
| Agree | Make the change. |
| Already handled | Point at the commit or line that handles it. |
| Disagree | Change nothing. Give the reason in the reply, or in the summary entry on a colleague's thread. |
| Needs the user | Leave open, decide nothing, list as pending. |
| Asks for nothing | A thread opening with `Note:`, an observation or praise. Post nothing and change nothing. |

### Verify a claim before you agree with it

A finding that asserts how a dependency, an API or the code behaves is a claim, not the
truth, whoever wrote it, bots included. Before an Agree that changes code, hand each such
claim to the `review-claim-verifier` agent, one claim per spawn. Pass the repository, PR
number, head sha, checkout, the claim, its anchor, its `claim_type` and the evidence the
thread offers. Never pass who wrote it. The verdict decides the outcome:

- `confirmed`: Agree, and cite the verifier's evidence in the reply.
- `refuted`: Disagree, and the reply gives the correction and its source.
- `unsupported`: Needs the user, with what the verifier could not establish. Change nothing
  on the claim's word alone.

A finding that asks for a preference rather than asserting a fact, such as a name, a style
or a missing test, needs no verifier.

Verify the way the project expects, such as build, tests and lint. Then commit and push once
for the whole pass, before any reply or summary. A line you link must point at pushed code.
Make one commit per coherent group of feedback.

## Write the reply

Reply on your own and bot threads only. Two lines is usually the whole reply, under the same
rules as `pr-description` at one-comment scale. Verify every claim against the pushed diff;
that is what makes resolving safe.

| Instead of | Write |
| --- | --- |
| Fixed! | `flush()` now holds the lock across queue-and-write. |
| Refactored as suggested. | Split `handler.rs` into `parse.rs` and `dispatch.rs`. No behavioural change. |
| I don't think that's an issue. | Keeping the retry. The upstream 429 needs the backoff. Comment added at `http.rs:42`. |

No restating the comment, no thanks, no offer of more. Name no person. If a thread needs
someone else, say what is undecided and leave it in the report; the user pulls them in.

Link with a permalink built from the pushed head SHA, and only if the change sits somewhere
the thread does not already sit:

```bash
gh pr view <number> --json headRefOid --jq .headRefOid
# https://github.com/<owner>/<repo>/blob/<headRefOid>/<path>#L<start>-L<end>
```

Check the thread's first author once more, then reply to the first comment's `databaseId`. A
top-level comment loses the code context and cannot be resolved.

```bash
gh api --method POST \
  repos/<owner>/<repo>/pulls/<number>/comments/<databaseId>/replies \
  -f body='<reply>'
```

## Resolve the user's threads only

Resolve a thread only if all of these hold:

- the user opened it,
- a `Botler` comment of theirs asked for something,
- the fix is pushed or the decline is reasoned,
- the reply is posted.

Leave a bot thread open; closing it is the user's call. Never resolve a colleague's thread
or one pending on the user. If unsure, leave it open and say so.

```bash
gh api graphql -f query='
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
}' -F threadId=<thread id>
```

## Summary of colleague threads

One summary per PR covering the threads a colleague opened, comment by comment in thread
order. The user reads it before writing back to the reviewer.

```
*<repo>#<number>*: <PR title>
<PR url>

*<reviewer>* `<path>:<line>`
> <the comment, trimmed to its point>
addressed: <what changed> . <permalink>

*<reviewer>* general comment
> <comment>
pending: <what is undecided>

<n> addressed . <n> declined . <n> pending
```

Each entry is labelled `addressed`, `declined: <reason>` or `pending`. The reviewer label is
plain text, never a Slack mention (`<@U...>`).

Draft it for `#pr-reviews` with `slack_send_message_draft`, or show the text in the session.
The user sends it; you never post it. A headless session puts the summary in its final
message instead. With no colleague thread, there is no summary.

## Notes

- Post no top-level PR comment and submit no review. The one exception is the merge-danger
  comment `pr-description` keeps: edit it in place if the fixes change what merging risks.
- A finding no inline thread carries gets the fix and a line in the summary or the session
  report, and nothing on the PR.
- A request outside the PR's scope gets no wider diff. Say so in the reply, or in the summary
  for a colleague's thread.
- If the review changed what the PR does, update the body with `pr-description`.
