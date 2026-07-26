#!/usr/bin/env bash
set -uo pipefail

# Reusable, non-sudo macOS cache cleanup.
# Safe to run manually (alias: clean) or from launchd.
# System nix generations are pruned by `updm` instead (they need sudo).
#
# Запуск: ./cleanup-mac.sh [--dry-run] [--deep]
#   --dry-run  показать, что было бы удалено, ничего не трогая
#   --deep     дополнительно снести дорого-восстанавливаемые кэши
#              (скомпилированные ANE-модели Hyprnote — пересоберутся при
#              следующем запуске приложения, первый старт будет долгим)
#
# Намеренно НЕ трогаем: ~/.lima (образы pxe-лабы), UTM-машины, данные
# Spokenly, диск OrbStack и его контейнеры — только висячие слои и build cache.

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

# Удаляет каталог/файл, засчитывая освобождённое. Под --dry-run только считает.
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

# Обёртка для чистилок пакетных менеджеров: они считают освобождённое сами.
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
# --force: обойти лок, который держит всегда запущенный timing-mcp. prune
# удаляет только неиспользуемые архивы, работающему серверу это безопасно.
UV_LOCK_TIMEOUT=10 run_tool "uv" uv cache prune --force
# Политика сборки мусора ОДНА на весь мак и задана в updm (tools/zsh/.zshrc) —
# здесь она повторяется, а не переопределяется. Раньше тут стоял `-d`, который
# сносит все старые генерации всех профилей («makes rollbacks impossible»).
# Сегодня это безвредно: без root системный профиль недосягаем, поколения целы.
# Но стоит скрипту переехать в launchd-демон (например, ради /Library/Updates) —
# и тот же `-d` молча обнулит откат. Расхождение убрано до того, как выстрелит.
run_tool "nix (профиль пользователя)" nix-collect-garbage --delete-older-than 3d

# Только висячие слои и кэш сборки. Ни `system prune -a`, ни удаления
# контейнеров: рабочие образы devpod должны пережить чистку.
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
# Скачанные .vsix остаются лежать после установки расширения; CachedData —
# прогретый JS-байткод, VS Code соберёт его заново при первом запуске.
reclaim "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" "VS Code: пакеты расширений"
reclaim "$HOME/Library/Application Support/Code/CachedData" "VS Code: прогретый код"

log "Кэши сборки..."
reclaim "$HOME/Library/Caches/go-build" "кэш сборки Go"
reclaim "$HOME/Library/Caches/pip" "кэш pip"

# Sparkle/Tauri складывают сюда скачанные установщики обновлений и не убирают
# их за собой — после установки это мёртвый груз.
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
