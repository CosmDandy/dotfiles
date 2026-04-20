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
  docker exec -u vscode -e HOME=/home/vscode -e USER=vscode "$name" bash -c '
    . ~/.nix-profile/etc/profile.d/nix.sh
    cd ~/dotfiles
    git remote set-url origin https://github.com/CosmDandy/dotfiles.git
    git -c submodule.recurse=false fetch origin
    git checkout @{u} -- . ':!tools/claude/custom'
    export NIXPKGS_ALLOW_UNFREE=1
    nix-channel --update
    if nix-env --upgrade --dry-run 2>&1 | grep -q "upgrading"; then
      nix-env --upgrade
    else
      echo "Nix packages are up to date"
    fi
  ' && echo "$LOG_PREFIX OK: $name ($workspace)" || echo "$LOG_PREFIX FAILED: $name ($workspace)"

  if $was_stopped; then
    echo "$LOG_PREFIX Stopping container back: $name ($workspace)"
    docker stop "$name"
  fi
done <<< "$CONTAINERS"

echo "$LOG_PREFIX Done"
