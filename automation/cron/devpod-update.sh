#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[devpod-update]"

CONTAINERS=$(docker ps -a --filter "label=devpod.user" --format '{{.Names}} {{.State}}')

if [[ -z "$CONTAINERS" ]]; then
  echo "$LOG_PREFIX No devpod containers found"
  exit 0
fi

while read -r name state; do
  [[ -z "$name" ]] && continue
  workspace=$(docker inspect "$name" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' | grep '\.devpod/agent' | sed 's|.*/workspaces/||;s|/content||')
  was_stopped=false

  if [[ "$state" != "running" ]]; then
    echo "$LOG_PREFIX Starting stopped container: $name ($workspace)"
    docker start "$name"
    was_stopped=true
    sleep 5
  fi

  echo "$LOG_PREFIX Updating: $name ($workspace)"
  docker exec -u cosmdandy -e HOME=/home/cosmdandy -e USER=cosmdandy "$name" bash -c '
    . ~/.nix-profile/etc/profile.d/nix.sh
    cd ~/dotfiles
    git remote set-url origin https://github.com/CosmDandy/dotfiles.git
    git -c submodule.recurse=false fetch origin
    # NOTE: `git checkout @{u} -- .` overwrites the working tree WITHOUT warning — an edit
    # made in the container and not yet committed vanished at 02:50 without a trace, across
    # every container at once. So the guard checks exactly what checkout can destroy:
    # changes to TRACKED files. Untracked files and submodule working trees are excluded, or
    # one stray file would put the container into permanent SKIPPED with nobody to notice.
    if [[ -n "$(git status --porcelain --untracked-files=no --ignore-submodules=all -- . ':!tools/claude/custom')" ]]; then
      git status --short --untracked-files=no --ignore-submodules=all -- . ':!tools/claude/custom' | head -20
      exit 3
    fi
    git checkout @{u} -- . ':!tools/claude/custom'
    if [[ ! -f ~/.dotfiles-profile ]]; then
      echo "legacy container (pre-home-manager) — recreate workspace to migrate"
      exit 0
    fi
    PROFILE=$(cat ~/.dotfiles-profile)
    home-manager switch --flake ~/dotfiles/platform/nix#$(whoami)-$PROFILE-$(uname -m)-linux -b hm-backup
  ' && rc=0 || rc=$?
  # NOTE: the code is captured immediately — inside `if ! cmd` it would be the negation.
  # 3 is a deliberate skip because of uncommitted work, not a failure.
  case "$rc" in
    0) echo "$LOG_PREFIX OK: $name ($workspace)" ;;
    3) echo "$LOG_PREFIX SKIPPED (незакоммиченные изменения): $name ($workspace)" ;;
    *) echo "$LOG_PREFIX FAILED (код $rc): $name ($workspace)" ;;
  esac

  if $was_stopped; then
    echo "$LOG_PREFIX Stopping container back: $name ($workspace)"
    docker stop "$name"
  fi
done <<< "$CONTAINERS"

echo "$LOG_PREFIX Done"
