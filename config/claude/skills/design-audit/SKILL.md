---
name: design-audit
description: Audit one rendered component against the nest design system, its spacing measured from the DOM and its look judged by Jev from a screenshot crop, then decide what each deviation becomes. Use for every new or changed screen in a QA story or a visual comparison.
---

# Design audit

A component complies when its spacing sits on the theme's grid and it looks like the
established app: the theme's typeface, input variant, palette and corner radius, and nothing
clipped. The theme in nest's `libraries/typescript/ui-base/src/themes/` is the standard, and
`scripts/rubric.json` holds the numbers this skill checks from it.

Two sources measure, and you decide.

- **The DOM probe** reads computed padding, margin, gap, corner radius, typeface and input
  variant from the live page, and the position of every field, text block and action. Code
  settles these, so a probe violation is a deviation.
- **Jev** (Jev 1.14, images) answers four yes/no questions about a crop of the component:
  a typeface other than the theme's sans-serif, outlined text fields, clipped or overlapping
  text, and a colour outside the palette. Jev cannot see a spacing difference of a few pixels
  in a screenshot. It scored two touching fields as evenly spaced on a test dialog, so it is
  never asked about spacing or alignment.

## 1. Score

With the page open in an `agent-browser` session, in the state to audit:

```
node ~/.claude/skills/design-audit/scripts/design-score.ts --text \
  --session <s> --selector '<css of the component root>' \
  --target '<what the component is, e.g. the create worker dialog>' \
  --out <dir> --name <file stem>
```

Pick the selector of the component the change renders, such as `.MuiDialog-paper` for a
dialog or the card's `data-testid`, not `body`. The probe scrolls it into view, and the
screenshot and crop are written to `<dir>/<name>-screen.png` and `<dir>/<name>-crop.png`.

From a screenshot alone, when no session holds the page:

```
node ~/.claude/skills/design-audit/scripts/design-score.ts --text \
  --screenshot <png> --target '<what the component is>' --out <dir> --name <file stem>
```

Jev finds the component with a Box question, so only the Jev half runs. When Jev does not see
the target the script exits 1 and says so. Name the target more specifically or pass the
session.

Drop `--text` for JSON, which is also written to `<dir>/<name>-design.json`. The script reads
`TYPESAFE_API_KEY`. When the key is missing or Jev fails, the probe's result still stands, the
report says `jev did not run`, and the verdict is `review` when the probe found nothing.

## 2. Read the verdict

| Verdict | Meaning |
|---|---|
| `complies` | The probe found nothing and every Jev answer is under 0.4. |
| `deviates` | The probe found a violation, or a Jev answer is 0.7 or above. |
| `review` | Only a Jev answer between 0.4 and 0.7, or Jev did not run. Look at the crop yourself and decide. |

Each `dom` line names the rule, the measured value and the element (its MUI classes, test id
and text). Each `jev` line names the signal and its probability.

| Signal | A deviation means |
|---|---|
| `dom spacing` | An author-set padding, margin or gap off the 4px grid (half steps of the 8px unit). MUI's own component slots pad off the grid by design and are not read. |
| `dom radius` | A rounded paper, card or dialog not rounded 8px. |
| `dom font` | Text set in a typeface the theme does not load. |
| `dom input-variant` | An outlined field in a form, or a filled one in a data grid. |
| `dom alignment` | A block (field, text, alert, card, table, divider) whose left edge is 3 to 24px off the edge most blocks in its column share. A larger offset is read as an intended indent or a second column. |
| `dom gap` | Three or more blocks of one kind stacked directly on each other with gaps that differ by more than 2px. A block of another kind between them, such as a section heading, starts a new run. |
| `dom actions` | A dialog or card action group that stops short of the end of its container, a contained button that is not last, or a dismiss action (Cancel, Close, Discard) after the confirming one. |
| `jev typeface` | Text that looks serif or otherwise off the theme's sans-serif. |
| `jev outlinedInput` | Text fields drawn as outlined boxes rather than filled. |
| `jev overflow` | Text cut off, clipped or overlapping. |
| `jev offPalette` | A button, link or accent in a colour outside the palette. |

The thresholds come from four test dialogs, not from the app's own screens. Read a Jev
`deviates` against the crop before acting on it: a probability says how sure Jev is, not that
the screen is wrong.

## 3. Decide each deviation

1. **Compare with the baseline.** Run the same audit on the reference: the established
   screen of the same kind, or X in a visual comparison. A deviation the reference shares is
   the app's, not the change's, and is reported as pre-existing.
2. **Find the source.** `git grep` the element's test id, text or translation key to reach
   the component file, then the `sx`, `styled` or prop that sets the value. A spacing
   violation names the property, so search for it near the component: `mt: 2.75` gives 22px.
3. **Name the fix.** The nearest grid value the reference uses (`mt: 2` or `mt: 3`, never a
   raw px value), the theme's variant (drop `variant="outlined"`), or the palette token
   (`color="primary"`). A clipped label usually wants the container to grow or the text to
   wrap, not a smaller font.

A deviation becomes a finding with its evidence: the `dom` line verbatim, or the Jev signal
and probability with the crop. Which findings get fixed, and where, is the caller's rule.

## Placing a new component

The audit checks these after the fact; follow them while building a view in nest. They are
read from nest's `ui-app` dialogs and its theme, so the established screens already agree.

- **Space with the theme.** Fields in a form sit 16px apart (`spacing={2}` on the `Stack` or
  `Grid`, the value in 31 of about 50 dialog layouts), 8px (`spacing={1}`) inside a compact
  group. Never a raw px value, and never a margin on one field to push it away from the next.
- **One column, one edge.** Everything in a column starts at the container's content edge.
  Indent only on purpose and by more than 24px, never a few pixels.
- **Group with headings, not gaps.** A new group of fields gets a heading or a divider, so the
  gaps within each group stay equal.
- **Actions at the end, confirm last.** A dialog's actions sit at its bottom right: the dismiss
  action (Cancel, Close) first, the confirming one last and contained when the dialog has one.
  A destructive action that is not the confirm, such as Delete in an edit dialog, sits alone
  at the left with `justifyContent: 'space-between'`.
