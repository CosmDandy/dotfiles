#!/usr/bin/env bash
set -uo pipefail

# Reusable, non-sudo macOS cache cleanup. Safe to run by hand (alias: clean) or from
# launchd. System nix generations are pruned by `updm` instead — they need sudo.
#
# Usage: ./cleanup-mac.sh [--dry-run] [--deep]
#   --dry-run  show what would be removed, touch nothing
#   --deep     also drop expensive-to-rebuild caches (Hyprnote's compiled ANE models —
#              they come back on the next app launch, but that launch is slow)
#
# NOTE: deliberately untouched — ~/.lima (PXE lab images), UTM machines, Spokenly data,
# and the OrbStack disk with its containers; only dangling layers and the build cache go.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$HOME/.bun/bin:/usr/local/bin:/usr/bin:/bin"

LOG_PREFIX="[cleanup-mac]"
DRY_RUN=""
DEEP=""
FREED=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --deep)    DEEP=1 ;;
    *) echo "$LOG_PREFIX неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

log() { echo "$LOG_PREFIX $*"; }

human() {
  awk -v k="$1" 'BEGIN {
    if (k >= 1048576)   printf "%.1f ГБ", k / 1048576
    else if (k >= 1024) printf "%.0f МБ", k / 1024
    else                printf "%d КБ", k
  }'
}

free_kb() { df -k /System/Volumes/Data | awk 'NR==2 {print $4}'; }

# Removes a path and counts what it freed; under --dry-run it only counts.
reclaim() {
  local path="$1" label="$2" kb
  [[ -e "$path" ]] || return 0
  kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
  [[ -n "$kb" ]] || return 0
  [[ "$kb" -gt 0 ]] || return 0
  FREED=$((FREED + kb))
  if [[ -n "$DRY_RUN" ]]; then
    log "  · $label — $(human "$kb")"
  else
    rm -rf "$path" 2>/dev/null && log "  · $label — освобождено $(human "$kb")"
  fi
}

# Wrapper for package-manager cleaners, which count what they freed themselves.
run_tool() {
  local label="$1"; shift
  if [[ -n "$DRY_RUN" ]]; then
    log "  · $label — будет выполнено: $*"
    return 0
  fi
  "$@" >/dev/null 2>&1 || log "  · $label пропущен"
}

BEFORE=$(free_kb)
[[ -n "$DRY_RUN" ]] && log "режим dry-run: ничего не удаляется"

log "Пакетные менеджеры..."
run_tool "Homebrew" brew cleanup --prune=all
run_tool "npm" npm cache clean --force
command -v bun >/dev/null && run_tool "bun" bun pm cache rm
# NOTE: --force gets past the lock held by the always-running timing-mcp. prune only
# removes unused archives, which is safe for a running server.
UV_LOCK_TIMEOUT=10 run_tool "uv" uv cache prune --force
# NOTE: the GC policy is defined once, in updm, and repeated here rather than overridden.
# This used to be `-d`, which removes every old generation of every profile ("makes
# rollbacks impossible"). Harmless today — without root the system profile is out of reach
# — but the moment this script moves into a launchd daemon that `-d` would silently
# destroy the rollback.
run_tool "nix (профиль пользователя)" nix-collect-garbage --delete-older-than 3d

# NOTE: dangling layers and the build cache only. No `system prune -a` and no container
# removal — the working devpod images must survive the cleanup.
if docker info >/dev/null 2>&1; then
  log "Docker/OrbStack..."
  run_tool "висячие образы" docker image prune -f
  run_tool "кэш сборки" docker builder prune -f
else
  log "Docker не запущен — пропуск"
fi

log "Кэши приложений..."
reclaim "$HOME/Library/Caches/Arc" "кэш Arc"
reclaim "$HOME/.cache/nvim" "кэш Neovim"
# Downloaded .vsix files stay behind after an extension installs; CachedData is warmed JS
# bytecode VS Code rebuilds on the next launch.
reclaim "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" "VS Code: пакеты расширений"
reclaim "$HOME/Library/Application Support/Code/CachedData" "VS Code: прогретый код"

log "Кэши сборки..."
reclaim "$HOME/Library/Caches/go-build" "кэш сборки Go"
reclaim "$HOME/Library/Caches/pip" "кэш pip"

# Sparkle/Tauri leave downloaded update installers here and never clean up after
# themselves — dead weight once installed.
log "Скачанные обновления приложений..."
while IFS= read -r updates_dir; do
  reclaim "$updates_dir" "$(basename "$(dirname "$updates_dir")")"
done < <(find "$HOME/Library/Caches" -maxdepth 2 -type d -name updates 2>/dev/null)

if [[ -n "$DEEP" ]]; then
  log "Глубокая чистка..."
  reclaim "$HOME/Library/Caches/com.hyprnote.stable/com.apple.e5rt.e5bundlecache" \
    "скомпилированные ANE-модели Hyprnote"
fi

AFTER=$(free_kb)
log "Учтено к освобождению: $(human "$FREED")"
if [[ -z "$DRY_RUN" ]]; then
  DELTA=$((AFTER - BEFORE))
  [[ "$DELTA" -lt 0 ]] && DELTA=0
  log "Свободно на диске: $(human "$BEFORE") → $(human "$AFTER") (+$(human "$DELTA"))"
fi
log "Готово"
