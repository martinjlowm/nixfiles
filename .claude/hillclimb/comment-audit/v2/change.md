# Breadth pass: essay length as a hint, duplicate criteria, a sharper into-code question

Round 2's categorization found no single cause of the remaining train keep
failures large enough to clear the noise floor. This round bundles three
independent fixes for the three largest buckets, so it cannot attribute its
effect to any one of them.

- **Essay length (4 train cases).** The essay ratio added `trim` to a comment
  longer than 1.5 times its code. `linesGoverned` stops at the first blank
  line, so a file header or long doc comment is measured against one
  paragraph. Now, the ratio adds `length` to `uncertain` on a kept comment
  instead of an action.
- **Duplicate (2 train cases).** The duplicate question had no criteria. Now,
  yes means the same fact about the same thing, and no covers a different
  item, site or behaviour that shares names or topic.
- **Into-code (3 train cases).** The criteria now ask for a change that would
  say everything the comment says, and rule out a name that could only
  abbreviate it.

Thresholds are unchanged.

Risk: change cases h22 (intoCode +0.05) and h36 (intoCode +0.03) are blocked
only through into-code, so the sharper question can let them through.
