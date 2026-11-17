# Stop blocking a commit on uncertain signals when the verdict is keep

`needsDecision` blocked any comment whose verdict was `keep` but that carried
a signal near a threshold. On train, that rule alone blocked 7 of the 15 keep
cases (h01, h11, h18, h23, h26, l18, l20). Every rep of each had
`actions = [keep]`. SKILL.md reads `uncertain` as "decide yourself", not as a
finding.

Now, `--check` exits 3 only when a comment's actions leave out `keep`.
`--text` still prints kept comments with uncertain signals, through
`worthReading`.

Predicted on train: gate_correct 0.500 -> 0.792, keep passing 3/15 -> 10/15,
change blocking stays 9/9, because no change case has a `keep` verdict.

Risk on test: a change case that `verdict()` under-flags would now pass. If
recall drops, the analyzer's fallback is to keep blocking a kept comment
whose `historyMarkers` matched.
