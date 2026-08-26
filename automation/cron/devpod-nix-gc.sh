#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[devpod-nix-gc]"

# NOTE: `docker ps` without -a sees only RUNNING containers, and this cron fires at 02:30
# on Sunday when devpod containers are almost always stopped — so the script printed "No
# running devpod containers found", exited 0 and never cleaned anything, week after week.
# The price of that inaction was 15 GB of nix store inside a container (two chromiums, two
# ansibles, clang — all garbage from old home-manager generations) and ~19 GB reclaimable
# on the host.
# `ps -a` sees every container with its state; stopped ones are started below and stopped
# again afterwards, the same way devpod-update.sh does it.
CONTAINERS=$(docker ps -a --filter "label=devpod.user" --format '{{.Names}} {{.State}}')

if [[ -z "$CONTAINERS" ]]; then
  echo "$LOG_PREFIX No devpod containers found"
  exit 0
fi

while read -r name state; do
  [[ -z "$name" ]] && continue
  was_stopped=false

  if [[ "$state" != "running" ]]; then
    echo "$LOG_PREFIX Starting stopped container: $name"
    docker start "$name"
    was_stopped=true
    sleep 5
  fi

  echo "$LOG_PREFIX Cleaning: $name"
  docker exec -u cosmdandy -e HOME=/home/cosmdandy -e USER=cosmdandy "$name" bash -c '
    . ~/.nix-profile/etc/profile.d/nix.sh
    nix-collect-garbage -d
  ' && rc=0 || rc=$?
  # NOTE: the code is captured immediately — inside `if ! cmd` it would be the result of
  # the negation rather than of the command.
  case "$rc" in
    0) echo "$LOG_PREFIX OK: $name" ;;
    *) echo "$LOG_PREFIX FAILED (код $rc): $name" ;;
  esac

  if $was_stopped; then
    echo "$LOG_PREFIX Stopping container back: $name"
    docker stop "$name"
  fi
done <<< "$CONTAINERS"

echo "$LOG_PREFIX Done"
