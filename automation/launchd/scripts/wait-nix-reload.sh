#!/usr/bin/env bash
set -uo pipefail

# Страховка от гонки загрузки: /nix лежит на отдельном ЗАШИФРОВАННОМ томе с
# `noauto` в /etc/fstab, и монтирует его determinate-nixd — последней фазой
# своего init, уже после nix-configuration и certificates. Замер загрузки
# 2026-08-16: boot 12:40:15, login items стартуют 12:40:40, /nix смонтирован
# только 12:40:51. Приложения, читающие конфиг на логине, эти 11 секунд видят
# висячий симлинк и молча берут дефолт — так AeroSpace каждый раз терял
# раскладку окон.
#
# Прямые симлинки в home/darwin.nix (хук loginItemConfigs) убирают /nix с пути
# к конфигу и лечат причину. Этот агент — второй рубеж: он ждёт появления
# /nix и просит AeroSpace перечитать конфиг. Нужен для случаев, когда
# приложение успело стартовать раньше активации симлинков, и на будущее — для
# любого нового login item, конфиг которого поедет через store.
#
# Запуск: ./wait-nix-reload.sh [--timeout N]

LOG_PREFIX="[wait-nix-reload]"
TIMEOUT=90

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "$LOG_PREFIX неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

log() { echo "$LOG_PREFIX $*"; }

# mount(8), а не test -d: точка /nix существует всегда — её создаёт
# synthetic.conf на этапе загрузки, задолго до того как том смонтирован.
nix_mounted() { /sbin/mount | grep -q ' on /nix ('; }

waited=0
until nix_mounted; do
  if (( waited >= TIMEOUT )); then
    log "/nix не смонтирован за ${TIMEOUT}s — выходим, перезагружать нечего"
    exit 0
  fi
  sleep 1
  waited=$((waited + 1))
done

if (( waited > 0 )); then
  log "/nix смонтирован через ${waited}s после старта агента"
else
  log "/nix уже был смонтирован"
fi

# AeroSpace перечитывает конфиг только по команде. Если он не запущен, CLI
# вернёт ошибку — это не повод падать: агент отработал свою задачу.
if /usr/bin/pgrep -qx AeroSpace; then
  if aerospace reload-config 2>/dev/null; then
    log "AeroSpace: конфиг перечитан"
  else
    log "AeroSpace: reload-config не отработал (CLI недоступен?)"
  fi
else
  log "AeroSpace не запущен — пропуск"
fi
