---
description: Create one scoped Conventional Commit and push its branch
argument-hint: "[scope]"
---
Create one Conventional Commit and push it. Scope: ${@:-the current task only}. Follow the repository's Git instructions.

1. Inspect `git status --short`, `git diff --cached`, and `git diff`. Review untracked files in scope. If the scope is ambiguous, intended and unrelated changes share a file, or unrelated changes are already staged, stop and ask before changing the index. If there is nothing to commit in scope, say so and stop.
2. Confirm the current branch and push destination. Use its configured upstream or a destination the user specified. With no upstream, use the same branch name on `origin` and set its upstream only if `origin` is the sole remote. If the destination is unclear, stop and ask.
3. Stage only explicit paths confirmed in status. Do not alter unrelated changes. Recheck the staged diff, then create one Conventional Commit only if the entire staged diff matches the scope.
4. After a successful commit, verify that the push would not publish other unpublished commits. If it would, ask before pushing. Dry-run an explicit push of only the current branch, then run the same push without `--dry-run`. Never force-push, amend, rebase, or skip hooks.
5. Verify the remote branch points at the new commit. Run `git status --short` and report the commit, destination, and any remaining changes. If the push fails, say the commit is still local and report the reason.
