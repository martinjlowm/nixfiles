---
name: pr-review
description: Run the multi-angle PR review pipeline on one pull request from this laptop. Leaves a pending review on a colleague's PR, or lists the findings for one of your own.
disable-model-invocation: true
argument-hint: "[<number> | <url>] [mono]"
---

# Review one pull request with the pipeline

`pr-review-orchestrator` owns the review: it fans out the `review-*` subagents, verifies
blockers and records the result. This skill is the main thread around it. It gathers the
inputs the orchestrator takes from its prompt, spawns it, and acts on the handoff object it
returns. The review stays the user's: a colleague's PR ends with a pending review that
`martinjlowm` reads and sends, and the user's own PR ends with findings in the terminal.

## 1. Resolve the pull request

The arguments name the PR as a number, a URL, or nothing for the PR of the current branch.
The word `mono` anywhere in them turns on the monomorphization review in step 3.

```bash
gh pr view <number-or-url> --json number,url,author,headRefName,headRefOid,baseRefName,state
gh api user --jq .login
```

Take the repository as `<owner>/<name>` from `url`, and the review owner from the second
command. The step is done when you hold the repository, number, author login, head ref,
head sha, base ref and review owner. A closed or merged PR, or no PR at all, ends the run
with that said to the user.

## 2. Check out the head

The orchestrator and its reviewers read the code at the head sha and write their results
under `<checkout>/.pr-review/`, so they get a detached worktree of their own and the user's
working tree stays as it is.

The current directory has to be a clone of the PR's repository, which
`gh repo view --json nameWithOwner` confirms. When it is not, stop and ask the user to run
the skill from a checkout of `<owner>/<name>`.

```bash
checkout=${TMPDIR%/}/pr-review/<owner>-<name>-<number>
git fetch origin pull/<number>/head
git worktree add --detach "$checkout" <head sha>   # first review of this PR
git -C "$checkout" checkout --detach <head sha>    # a worktree from an earlier review
```

The step is done when `git -C "$checkout" rev-parse HEAD` prints the head sha.

## 3. Spawn the orchestrator

Spawn `pr-review-orchestrator` with the Agent tool and this prompt:

```
Review pull request <owner>/<name>#<number>.
Repository: <owner>/<name>
PR number: <number>
Author: <author login>
Head ref: <head ref>
Head sha: <head sha>
Local checkout: <checkout>
Review owner: <review owner>
Delivery: by_author
Visual review: none
Mono-item review: <none, or the block below when the arguments hold `mono`>
```

The mono-item block names the Rust paths:

```
Rust paths: *.rs, Cargo.toml, Cargo.lock
```

The visual review stays `none`, because its staging credential command exists nowhere yet
and the run would always end `skipped`.

The orchestrator runs in the background and its completion arrives as a notification. A
review takes up to 30 minutes, and up to two and a half hours with the monomorphization
review. Tell the user it is running and which mode it will end in, then wait for the
notification. The step is done when the handoff object arrives.

## 4. Act on the handoff

The handoff is a JSON object. Its `mode` picks the ending.

| `mode` | What you do |
| --- | --- |
| `skipped` | Name the reason in `degraded_angles`: a review of this head sha exists, or another run holds it. |
| `empty` | Tell the user the reviewers found nothing. Post nothing. |
| `pending_review` | Audit the pending review, then hand it to the user. |
| `draft_file` | Present the findings from `draft_path` in the terminal. Post nothing. |

### Auditing a pending review

The orchestrator wrote every finding to `<checkout>/.pr-review/<number>-<head sha>.json`
and created the review as the owner. Read both:

```bash
gh-as-owner api repos/<owner>/<name>/pulls/<number>/reviews/<review_id>
gh-as-owner api repos/<owner>/<name>/pulls/<number>/reviews/<review_id>/comments
```

The review passes when its state is `PENDING`, its body opens on `## Verdict:` with the
verdict from the handoff, it holds `comment_count` comments, and each comment matches a
finding in the audit record by path and range. Correct a body that fails with a `PUT` on the
review, as the orchestrator's phase 4 does. Report a comment that matches no finding to the
user rather than deleting it.

Then give the user the PR's URL, the verdict, the comment count, and the blockers
confirmed, refuted and demoted. The review is theirs to read, edit and submit from the
PR's "Files changed" tab, so leave it `PENDING`.

### Presenting a draft file

On the user's own PR GitHub refuses a `REQUEST_CHANGES` review, and the user is fixing the
code rather than reviewing it. List the findings from `draft_path`, blockers first, each as
`path:line` or `path:start_line-line`, its severity and its body, so the user can act on them here. A
`scope_report_path` holds the split plan when the PR solves more than one problem; give it
after the findings. Offer to fix them, and post nothing to the PR.

### What every ending reports

- Each entry in `degraded_angles` other than the skip reasons, since that angle never
  reviewed the PR.
- An `unverified_count` above zero, which means some blockers went unchecked against their
  sources and need closer reading.
- `visual`, `mono_items` and `scope` when they are anything other than `not_applicable`,
  with the report path when there is one.

Leave the worktree in place: a later review of the same PR reuses it. `git worktree remove
<checkout>` from the clone deletes it.
