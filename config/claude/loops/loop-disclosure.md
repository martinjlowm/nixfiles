## Disclosure

This loop runs unattended, and everything it posts carries the user's name. Mark that work as
an agent's:

- Every commit message you write ends with the trailer
  `Assisted-by: Claude Code (unattended loop)`.
- Every PR body you write or rewrite carries the same trailer, last in its trailer block. This
  overrides the `pr-description` skill's rule against agent attribution.
- Every comment and review-thread reply you post ends with
  `<sub>Posted by an unattended Claude Code loop.</sub>` on its own line.
