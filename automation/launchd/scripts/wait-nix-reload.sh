#!/usr/bin/env bash
set -uo pipefail

# Insurance against the boot race: /nix sits on a separate ENCRYPTED volume with `noauto`
# in fstab, mounted by determinate-nixd as the last phase of its init. Measured 2026-08-16:
# boot 12:40:15, login items start 12:40:40, /nix mounted only at 12:40:51. For those
# eleven seconds an app reading its config through the store sees a dangling symlink and
# silently takes the default — which is how AeroSpace lost its layout every time.
#
# The direct symlinks in home/darwin.nix fix the cause by keeping /nix off that path. This
# agent is the second line: it waits for the mount and asks AeroSpace to reload. It covers
# an app that started before the symlinks were in place, and any future login item whose
# config does go through the store.
#
# Usage: ./wait-nix-reload.sh [--timeout N]

LOG_PREFIX="[wait-nix-reload]"
TIMEOUT=90

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "$LOG_PREFIX неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
done

log() { echo "$LOG_PREFIX $*"; }

# NOTE: mount(8), not test -d — the /nix mountpoint always exists, created by
# synthetic.conf early in boot, long before the volume is there.
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

# AeroSpace only rereads its config on command. A missing CLI is not a reason to fail —
# the agent has done its job.
if /usr/bin/pgrep -qx AeroSpace; then
  if aerospace reload-config 2>/dev/null; then
    log "AeroSpace: конфиг перечитан"
  else
    log "AeroSpace: reload-config не отработал (CLI недоступен?)"
  fi
else
  log "AeroSpace не запущен — пропуск"
fi
