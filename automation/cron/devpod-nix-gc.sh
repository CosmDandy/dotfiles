#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[devpod-nix-gc]"

# docker ps (без -a) видит только ЗАПУЩЕННЫЕ контейнеры. Cron стоит в 02:30
# по воскресеньям, когда devpod-контейнеры почти всегда остановлены — поэтому
# скрипт печатал "No running devpod containers found" и выходил кодом 0, ни разу
# ничего не почистив. Каждая запись в journal подтверждает:
#   Jul 26 02:30  [devpod-nix-gc] No running devpod containers found
#   Aug 02 02:30  [devpod-nix-gc] No running devpod containers found
# Цена бездействия — 15 ГБ nix store в контейнере (две версии chromium по
# 700 МБ, две копии ansible по 620 МБ, clang 814 МБ: всё мусор от старых
# поколений home-manager, в текущем профиле его нет) и 18.98 ГБ reclaimable
# на самом хосте.
# ps -a видит все контейнеры вместе с состоянием, а остановленные поднимаются
# ниже перед чисткой и гасятся обратно — как в devpod-update.sh.
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
  # Код снимается сразу: внутри `if ! cmd` это был бы результат отрицания,
  # а не самой команды.
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
