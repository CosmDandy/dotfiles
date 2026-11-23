#!/usr/bin/env bash
set -euo pipefail

# A stopped workspace stays stopped. A racing stop makes exec fail, not start it.
containers=$(docker ps --filter 'label=devpod.user' --format '{{.Names}}')
rc=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  echo "[devpod-update] $name"
  docker exec -u cosmdandy -e HOME=/home/cosmdandy "$name" sh -ec '
    cd "$HOME/dotfiles"
    branch=$(git branch --show-current)
    # A previous pull can advance a gitlink without updating its private checkout.
    changes=$(git status --porcelain --untracked-files=normal --ignore-submodules=all)
    if [ "$branch" != main ] || [ -n "$changes" ] || ! git diff --cached --quiet --ignore-submodules=dirty; then
      echo "Skipping: not a clean main checkout"
      exit 0
    fi
    # Cron has no SSH agent. Keep the interactive origin and private submodules untouched.
    GIT_TERMINAL_PROMPT=0 git -c submodule.recurse=false pull --ff-only --no-recurse-submodules https://github.com/CosmDandy/dotfiles.git main
  ' || { echo "[devpod-update] FAILED: $name" >&2; rc=1; }
done <<< "$containers"
exit "$rc"
