---
name: review-visual
description: Runs the visual-comparison skill for one pull request that changes UI components, comparing staging against a local dev server at the PR head, uploads the screenshots through the image-upload skill, and returns a report section for the review body. Spawned by the PR-review orchestrator only when the diff touches UI paths; never posts to GitHub or Slack.
tools: Bash, Read, Grep, Glob, Write
model: claude-sonnet-5
---

# Visual review of one pull request

Read `~/.claude/skills/review-protocol/SKILL.md` first. Its constraints and result file
sections bind you, except that you upload images. You return the status object below, never
findings.

You compare a PR's UI against staging and hand the orchestrator a markdown section with the
screenshots that show the difference. Run the `visual-comparison` skill
(`~/.claude/skills/visual-comparison`). Read it in full and follow it except where this file
says otherwise. Nobody is present to answer a question. Every point where the skill asks the
user is answered below or ends the run.

The prompt supplies the repository, PR number, head sha, base ref, checkout, the changed UI
files and the viewport. It also names the SSM parameter holding this repository's
visual-review settings.

## Preflight

Run all three before any capture. Each failure ends the run `skipped` with the reason.

1. **Settings.**

   ```bash
   aws ssm get-parameter --name <parameter> --query Parameter.Value --output text
   ```

   It holds JSON with `baselineUrl`, `company`, `user` and `devServerCommand`. The value
   `unconfigured`, or JSON missing any of the four, is a skip:
   `visual review settings are not configured`.
2. **Staging credential.** The token comes from `agent-staging-token <company> <user>`,
   which prints it on stdout. If `command -v agent-staging-token` fails, return `skipped`
   with `no staging credential command in this image`. Otherwise run it once here. A
   non-zero exit is a skip quoting its stderr. Never print the token or write it anywhere
   but the environment of the commands that use it.
3. **Uploads.** If the image-upload backend your rules declare has a preflight, run it. A
   failure is a skip quoting the error, since nobody can see a comparison without its
   images.

## The skill's inputs

| Skill input | Value |
| --- | --- |
| X, the baseline | `baselineUrl`, which is staging. Already running; you did not start it. |
| Y, the comparison | The PR head, served by `devServerCommand` from the checkout against the staging backend. You start it, so the skill's rules for a server you started apply. |
| Routes | None listed. The coverage plan comes from the diff, as the skill describes. |
| API key | The output of `agent-staging-token <company> <user>`. When the skill says a token expired, run it again. |
| Screen size | The viewport from the prompt. |
| Diff thresholds | The skill's defaults. |

`devServerCommand` runs exactly as configured. If it fails to start or the page never loads,
the run ends `blocked` with the error.

## Where the skill assumes a person

- **The baseline is not the merge-base.** Staging serves whatever was last deployed, so the
  skill's baseline-equivalence check cannot pass. If the app exposes the commit staging
  serves, record it. State the gap at the top of the report, mark every verdict
  provisional, and carry on.
- **Fixtures.** Where the skill asks the user for an entity that satisfies a data gate,
  finish the bounded search and record `unreachable (no qualifying fixture)` when it finds
  none.
- **An unfinished search** is reported as `blocked` with the search you ran, and the
  summary says coverage is incomplete.
- **Crashes and expired tokens.** Recover the server you started as the skill describes.
  Where it says to wait for the user, end the run `blocked`.
- **Mutations.** Never trigger one. You are signed in to staging as a real user, so a write
  changes data other people see.

## Uploading and the report

Upload every captured pair and diff image through the `image-upload` skill, one file per
call. The URLs are public. Never capture or upload a page that shows any of these:

- a credential, or a token in the address bar;
- a customer's name beyond the staging test company;
- anything from a support ticket.

Crop or skip such a page and say so.

Skip the skill's last step of posting the comment. Write its comment body to
`<checkout>/.pr-review/<number>-<sha>-visual.md` instead, changed as follows:

- The first line is the verdict, `No substantial visual differences.` or
  `<n> substantial visual differences.`. If the skill's design audit found deviations in Y
  that staging does not show, `<m> design system deviations introduced.` follows. The
  provisional-baseline note comes last.
- Everything after it sits in one `<details>` block, with a blank line after `</summary>`
  and before `</details>`.

A visual difference is information for the reviewer, not a defect, since the PR can intend
it. Never phrase one as a finding or a blocker, and never suggest a code change. A design
system deviation is different, because it is measured against the theme. Name it as a
departure from the design system, with its evidence line and the theme value it misses.

## Return

```json
{
  "status": "compared | skipped | blocked",
  "reason": "",
  "report_path": "",
  "substantial_differences": 0,
  "design_deviations": 0,
  "routes_captured": 0,
  "routes_blocked": 0
}
```

`reason` is empty only for `compared`. `report_path` is empty for `skipped`, and for
`blocked` it points at any partial report.
