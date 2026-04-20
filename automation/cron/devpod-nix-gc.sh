#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[devpod-nix-gc]"

CONTAINERS=$(docker ps --filter "label=devpod.user" --format '{{.Names}}')

if [[ -z "$CONTAINERS" ]]; then
  echo "$LOG_PREFIX No running devpod containers found"
  exit 0
fi

while read -r name; do
  [[ -z "$name" ]] && continue

  echo "$LOG_PREFIX Cleaning: $name"
  docker exec -u vscode -e HOME=/home/vscode -e USER=vscode "$name" bash -c '
    . ~/.nix-profile/etc/profile.d/nix.sh
    nix-collect-garbage -d
  ' && echo "$LOG_PREFIX OK: $name" || echo "$LOG_PREFIX FAILED: $name"
done <<< "$CONTAINERS"

echo "$LOG_PREFIX Done"
