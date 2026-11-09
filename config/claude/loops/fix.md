# CI fix loop

Each run of this prompt is one iteration. It makes PR `__PR__` green: failing checks fixed,
conflicts resolved. `__REPO__` is the repository, or empty for the current one. If
`__REPO__` is non-empty, add `--repo __REPO__` to every `gh` call below that targets the PR.

## Scope gate

```
gh pr view __PR__ --json number,title,author,headRefName,baseRefName,state,statusCheckRollup,mergeable,url
gh api user --jq .login
```

Continue only if the PR is open and its author is the current user or `app/dependabot`. Any
other author owns the branch, so push nothing. Say the PR is out of scope and end with
`<promise>COMPLETE</promise>` so the loop stops.

## Workflow

1. Check out the branch with `gh pr checkout __PR__`. Enter the Nix dev shell, which installs
   the pre-commit hooks.
2. Sort each check in `statusCheckRollup` into passed, failed, cancelled or pending.
3. If every check passed and `mergeable` is not `CONFLICTING`: `<promise>COMPLETE</promise>`.
4. If nothing failed or was cancelled and checks are still pending, end the iteration.
5. Resolve conflicts by merging the base branch. Fix each failed or cancelled check at its
   root cause, per "CI triage". If a failure comes from unaddressed review feedback, the fix
   addresses that feedback. Handle its thread per the review-thread rules.
6. Commit as `fix(<component>): resolve CI failures for #__PR__`. Push without force.
7. Check once that the push started new runs with `gh pr checks __PR__`, then end the
   iteration. Never wait for CI.
