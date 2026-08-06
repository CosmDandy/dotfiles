#!/usr/bin/env bash
# Бэкап недекларативного в один зашифрованный restic-репозиторий на Hetzner
# Object Storage. Данные и секреты вместе — restic шифрует на клиенте, ssh-ключи
# в облаке в безопасности.
#
# Версии («как Time Machine») дают снапшоты restic + политика forget: держим
# 7 дневных, 4 недельных, 6 месячных, остальное подрезаем.
#
# Доступы и пароль репозитория — в ~/.config/restic/env (chmod 600, вне
# репозитория, образец: automation/backup/env.example). Файл нужен для
# автоматического запуска из launchd: rbw требует разблокированного хранилища
# и для фонового агента не годится. КАНОНИЧЕСКИЕ копии всех значений держать в
# Bitwarden — пароль репозитория, лежащий только внутри зашифрованного бэкапа,
# бесполезен: без него нечем расшифровать.
#
# Запуск: ./backup.sh [--dry-run]

set -uo pipefail

# launchd не наследует окружение интерактивного шелла — PATH задаём явно.
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Из launchd скрипт исполняется как store-путь (writeShellScriptBin кладёт туда
# ОДИН файл — текст скрипта), поэтому рядом с ним манифеста нет и SCRIPT_DIR как
# единственный источник ломал агента. Путь приходит переменной из
# darwin-configuration.nix; фолбэк на соседний файл оставлен для запуска руками
# из рабочей копии.
MANIFEST_FILE="${BACKUP_MANIFEST_FILE:-$SCRIPT_DIR/manifest.conf}"
ENV_FILE="${RESTIC_ENV_FILE:-$HOME/.config/restic/env}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && DRY_RUN="--dry-run"

log()  { echo "[backup] $*"; }
warn() { echo "[backup] ВНИМАНИЕ: $*" >&2; }

# Уведомление в Центр уведомлений macOS. Молчащий бэкап — худший вид сломанного:
# лог в /tmp никто не читает, и через полгода тишины кажется, что всё работает.
# Из launchd-агента (user session) osascript доступен; вне GUI просто не сработает.
notify() {
  [ -n "${BACKUP_NO_NOTIFY:-}" ] && return 0
  osascript -e "display notification \"$1\" with title \"Бэкап\" subtitle \"$2\" sound name \"Basso\"" \
    >/dev/null 2>&1 || true
}

die() {
  echo "[backup] ОШИБКА: $*" >&2
  notify "$*" "бэкап не выполнен"
  exit 1
}

command -v restic >/dev/null || die "restic не найден в PATH (добавлен в platform/nix, примени darwin-rebuild switch)"

[ -f "$MANIFEST_FILE" ] || die "не найден манифест $MANIFEST_FILE"
# shellcheck source=manifest.conf
source "$MANIFEST_FILE"

# Доступы: RESTIC_REPOSITORY, RESTIC_PASSWORD, AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY. Файл с секретами — только у владельца.
if [ ! -f "$ENV_FILE" ]; then
  die "нет файла доступов $ENV_FILE — создай по образцу automation/backup/env.example"
fi
# GNU-синтаксис первым: BSD не знает -c и падает молча, а GNU знает -f как
# --file-system и печатает в stdout блок про ФС вместо режима доступа.
perms=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null)
[ "$perms" = "600" ] || warn "$ENV_FILE с правами $perms — должно быть 600 (chmod 600 $ENV_FILE)"
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${RESTIC_REPOSITORY:?не задан в $ENV_FILE}"
: "${RESTIC_PASSWORD:?не задан в $ENV_FILE}"

log "репозиторий: $RESTIC_REPOSITORY"
[ -n "$DRY_RUN" ] && log "режим проверки, ничего не пишется"

# Репозиторий инициализируется вручную один раз (restic init) — не создаём его
# молча из скрипта: опечатка в имени бакета иначе завела бы новый пустой репо
# вместо ошибки.
if ! restic cat config >/dev/null 2>&1; then
  die "репозиторий недоступен или не инициализирован. Один раз: restic init"
fi

# --- бэкап ------------------------------------------------------------------

existing=()
for p in "${BACKUP_PATHS[@]}"; do
  [ -e "$p" ] && existing+=("$p") || warn "пропущен несуществующий путь: $p"
done
[ ${#existing[@]} -gt 0 ] || die "ни одного пути из BACKUP_PATHS не существует"

exclude_args=()
for e in "${EXCLUDES[@]}"; do exclude_args+=(--exclude="$e"); done

log "снимаю снапшот (${#existing[@]} путей)"
restic backup $DRY_RUN \
  --tag automated \
  --exclude-caches \
  --retry-lock 10m \
  "${exclude_args[@]}" \
  "${existing[@]}" \
  || die "restic backup завершился с ошибкой"

# Пропущенный путь не роняет бэкап, но означает, что что-то из ценного не
# сохранилось — про это надо знать, а не находить в логе через полгода.
if [ ${#existing[@]} -lt ${#BACKUP_PATHS[@]} ]; then
  notify "сохранено путей: ${#existing[@]} из ${#BACKUP_PATHS[@]}" "часть путей пропущена"
fi

# --- ротация версий ---------------------------------------------------------
# forget с --prune чистит и метаданные, и данные за один проход. dry-run её
# пропускает: без свежего снапшота она подрезала бы реальную историю.
if [ -z "$DRY_RUN" ]; then
  log "ротация: --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY"
  if ! restic forget --prune \
    --retry-lock 10m \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY"; then
    # Раньше это был обычный warn, неотличимый от «пропущен один путь» — а тут
    # политика хранения не применяется вообще, и объём в облаке молча растёт,
    # пока кто-то не заметит счёт (см. инцидент 2026-07-26: не применялось 10 дней).
    warn "restic forget --prune завершился с ошибкой — политика хранения НЕ применена, старые снапшоты копятся (снапшот при этом снят)"
    notify "forget --prune упал — старые версии не подрезаны, объём в репозитории растёт" "политика хранения НЕ применена"
  fi
fi

# --- итог -------------------------------------------------------------------

if [ -z "$DRY_RUN" ]; then
  # Считаем разбором JSON, а не grep по '"time"': это поле встречается и во
  # вложенных объектах, из-за чего счётчик врал (показывал 1 при двух снапшотах).
  log "снапшотов в репозитории: $(restic snapshots --json 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo '?')"
  log "готово"
fi
