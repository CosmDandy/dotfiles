---
description: Create one scoped Conventional Commit without pushing
argument-hint: "[scope]"
---
Create one local Conventional Commit. Scope: ${@:-the current task only}. Follow the repository's Git instructions.

1. Inspect `git status --short`, `git diff --cached`, and `git diff`. Review any untracked files in scope. If the scope is ambiguous, intended and unrelated changes share a file, or unrelated changes are already staged, stop and ask before changing the index. If there is nothing to commit in scope, say so and stop.
2. Stage only the intended files, using `git add --` with explicit paths confirmed in status. Never stage the whole tree. Do not unstage or alter unrelated changes. Recheck the staged diff and commit only if the entire staged diff matches the scope.
3. Use a Conventional Commit message. Run `git status --short` after the commit and report the hash, subject, and remaining changes. Do not amend, skip hooks, or push.
