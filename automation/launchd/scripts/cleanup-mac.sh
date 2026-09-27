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
# NOTE: deliberately untouched — ~/.lima (the PXE lab machines themselves, as opposed to
# ~/Library/Caches/lima, which is only downloaded base images and goes under --deep), UTM
# machines, Spokenly data, the speech model in ~/Library/Caches/qwen3-speech, the nvim
# plugin and mason trees (~1.3 GB, restored only by a very slow first launch), and the
# OrbStack disk with its containers; of docker, only dangling layers and the build cache.

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
  if [[ -n "$DRY_RUN" ]]; then
    FREED=$((FREED + kb))
    log "  · $label — $(human "$kb")"
  # NOTE: counted AFTER the removal succeeds, not before. rm silences its own
  # errors here, so a path that could not be deleted used to be added to the
  # total anyway and the closing "учтено к освобождению" overstated the result —
  # while the honest before/after figure right below it disagreed.
  elif rm -rf "$path" 2>/dev/null; then
    FREED=$((FREED + kb))
    log "  · $label — освобождено $(human "$kb")"
  fi
}

# Reports a size without touching anything. For caches that are cleaned by their
# own tool (which decides what is unused) but whose real footprint is worth
# seeing — otherwise a 400 MB directory stays invisible because the tool
# considers all of it live.
report() {
  local path="$1" label="$2" kb
  [[ -e "$path" ]] || return 0
  kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
  [[ -n "$kb" ]] || return 0
  log "  · $label — сейчас $(human "$kb"), не удаляется"
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
# NOTE: not a deletion at all — identical files in the store are replaced by hard
# links to one copy. The store is the biggest single thing on this disk (~6 GB)
# and the garbage collector above cannot touch what is still referenced, while
# this reclaims the duplication inside it. Slow (it hashes the store), which is
# why it runs after the collector rather than before.
run_tool "nix (дедупликация store)" nix-store --optimise

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
# NOTE: the EVALUATION cache, not the store — nix rebuilds it on the next command.
# Nothing else prunes it and it was the largest untouched directory in ~/.cache.
reclaim "$HOME/.cache/nix" "кэш вычисления nix"
# Application logs: individually tiny, collectively unbounded, and rotated by
# nobody.
reclaim "$HOME/Library/Logs" "логи приложений"

# uv is pruned above by its own cache command, which only drops what uv itself
# considers unused — the directory stays the biggest one in ~/.cache either way,
# so at least report its real size instead of leaving it invisible.
report "$HOME/.cache/uv" "кэш uv"

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
  # Browser binaries, restored by `playwright install`. Deep only: the download
  # is large and comes back over the network.
  reclaim "$HOME/Library/Caches/ms-playwright" "браузеры Playwright"
  # NOTE: this is the DOWNLOAD cache, a different thing from ~/.lima, which holds
  # the machines themselves and is never touched. Re-downloading a base image is
  # slow, hence deep only.
  reclaim "$HOME/Library/Caches/lima" "кэш образов lima"
fi

AFTER=$(free_kb)
log "Учтено к освобождению: $(human "$FREED")"
if [[ -z "$DRY_RUN" ]]; then
  DELTA=$((AFTER - BEFORE))
  [[ "$DELTA" -lt 0 ]] && DELTA=0
  log "Свободно на диске: $(human "$BEFORE") → $(human "$AFTER") (+$(human "$DELTA"))"
fi
log "Готово"
