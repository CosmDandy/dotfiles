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
    # git checkout @{u} -- . перезаписывает рабочее дерево БЕЗ предупреждения:
    # правка в ~/dotfiles внутри контейнера, не успевшая уехать в коммит,
    # пропадала в 02:50 без следа. Ночью, по всем контейнерам разом, включая
    # остановленные — их скрипт для этого сам поднимает.
    # Проверяем ровно то, что checkout способен затереть: изменения в
    # ОТСЛЕЖИВАЕМЫХ файлах. Untracked он не трогает, рабочие деревья сабмодулей
    # тоже — без этих двух флагов один случайный untracked-файл (или грязный
    # сабмодуль, который здесь обычно даже не инициализирован) отправлял бы
    # контейнер в вечный SKIPPED, и разгребать это было бы некому.
    # Сабмодуль custom исключён отдельно по той же причине, по какой исключён
    # из checkout: у него свой цикл жизни.
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
  # Код снимается сразу: внутри `if ! cmd` это был бы результат отрицания.
  # 3 — сознательный пропуск из-за незакоммиченной работы, не отказ.
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
