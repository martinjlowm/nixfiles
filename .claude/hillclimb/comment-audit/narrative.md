| round | change (one line) | test gate | train gate | test keep passed | test change blocked | train change blocked (all reps) | s/case |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | baseline | 0.316 | 0.350 | 2/28 | 10/10 | 11/11 | 0.62 |
| 1 | keep verdict ignores uncertain signals | 0.719 | 0.717 | 17/28 | 10/10 | 11/11 | 0.71 |
| 2 | breadth: essay hint, duplicate criteria, into-code criteria | 0.842 | 0.817 | 21/28 | 10/10 | 8/11 | 0.70 |
| **3** | **v2 without the into-code criteria (winner)** | **0.807** | **0.792** | **20/28** | **10/10** | **10/11** | 0.70 |

## Recommended change

Ship round 3. `--check` exits 3 only when a comment's verdict leaves out
`keep`, so an uncertain signal on a kept comment no longer blocks a commit.
A comment much longer than its code becomes an `uncertain: length` hint
instead of a `trim` action. The duplicate question gains criteria that
separate the same fact about the same thing from a related fact elsewhere.

## Versus baseline

On the 38 held-out test cases, strict gate_correct rose from 31.6% (95% CI
19 to 47) to 78.9% (64 to 89). Keep comments let through went from 2/28 to
20/28, and change comments blocked stayed 10/10. Of the test cases, 20
improved and none got worse.

## Why trust this

- The labels are human-verified, and the analyzer read only the train split.
- Round 1 alone clears the noise floor: 15 test keep cases moved and none
  regressed.
- Round 3 attributes round 2's bundle: removing the into-code edit brought
  back train recall on h22 and h36 and kept the essay-hint gains.
- Rounds 2 and 3 over round 1 are directional: +8.8 test points for round 3,
  against a noise floor of about +/-14.

## What else was tried

- Round 2's sharper into-code question freed h53 on train, but let change
  cases h22 and h36 through on some reps. No into-code threshold separates
  those keep and change cases (analysis/round2-categorization.md).
- A confidence gate on value-only removal was not run. It is worth about 2
  train cases, and it would put change case l03 at risk.
