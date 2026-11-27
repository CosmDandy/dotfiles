---
description: Create one scoped Conventional Commit, push its branch, and open a GitHub pull request
argument-hint: "[scope]"
---
Create one Conventional Commit, push it, and open a GitHub pull request. Scope: ${@:-the current task only}. Follow the repository's Git instructions.

1. Inspect `git status --short`, `git diff --cached`, and `git diff`. Review untracked files in scope. If the scope is ambiguous, intended and unrelated changes share a file, or unrelated changes are already staged, stop and ask before changing the index. If there is nothing to commit in scope, say so and stop.
2. Confirm the current branch and push destination. Use its configured upstream or a destination the user specified. With no upstream, use the same branch name on `origin` and set its upstream only if `origin` is the sole remote. Resolve the GitHub repository from the actual push URL and confirm that `gh` can read it. Use the requested PR base or the repository's default branch. Stop before committing if the destination or base is unclear, if the push would update the default branch or PR base, or if the branch is detached.
3. Stage only explicit paths confirmed in status. Do not alter unrelated changes. Recheck the staged diff, then create one Conventional Commit only if the entire staged diff matches the scope.
4. Check which commits the push would publish and review the full PR diff against the confirmed base. Ask before publishing other unpublished commits or opening a PR with out-of-scope changes. Dry-run an explicit push of only the current branch, then run the same push without `--dry-run`. Never force-push, amend, rebase, or skip hooks.
5. Verify that the remote branch points at the new commit before touching the PR. If an open PR already matches this repository, head, and base, return its URL without editing it. Otherwise use `gh pr create` with explicit `--repo`, `--head`, and `--base`. Summarize the full PR diff and report only checks actually run. Do not merge the PR.
6. Run `git status --short` and report the commit, push destination, PR URL, and remaining changes. If push or PR creation fails, stop and report which steps succeeded and why the next one failed.
