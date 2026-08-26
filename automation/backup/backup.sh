#!/usr/bin/env bash
# Backs up everything non-declarative into one encrypted restic repository on
# Hetzner Object Storage. Data and secrets together — restic encrypts
# client-side, so ssh keys are safe in the cloud. Versions come from restic
# snapshots plus a forget policy: 7 daily, 4 weekly, 6 monthly.
#
# Credentials and the repository password live in ~/.config/restic/env (mode
# 600, outside the repository, sample in env.example). A file rather than rbw,
# because rbw needs an unlocked vault and is no good for a background agent.
# NOTE: keep the canonical copies of every value in Bitwarden — a repository
# password stored only inside the encrypted backup cannot decrypt it.
#
# Usage: ./backup.sh [--dry-run]

set -uo pipefail

# NOTE: launchd inherits nothing from an interactive shell, so PATH is set
# explicitly.
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# NOTE: under launchd this runs as a store path, and writeShellScriptBin puts
# exactly ONE file there — so there is no manifest "next to the script" and
# SCRIPT_DIR as the only source broke the agent. The path arrives as an env var
# from darwin-configuration.nix; the neighbour-file fallback is for running it
# by hand from the working copy.
MANIFEST_FILE="${BACKUP_MANIFEST_FILE:-$SCRIPT_DIR/manifest.conf}"
ENV_FILE="${RESTIC_ENV_FILE:-$HOME/.config/restic/env}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && DRY_RUN="--dry-run"

log()  { echo "[backup] $*"; }
warn() { echo "[backup] ВНИМАНИЕ: $*" >&2; }

# NOTE: a silent backup is the worst kind of broken — nobody reads a log in
# /tmp, and after six months of silence it looks like everything works.
# osascript is available from a launchd user agent; outside a GUI session it
# simply does nothing.
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

if [ ! -f "$ENV_FILE" ]; then
  die "нет файла доступов $ENV_FILE — создай по образцу automation/backup/env.example"
fi
# NOTE: GNU form FIRST — BSD does not know -c and fails silently, while GNU
# reads -f as --file-system and prints a filesystem block into stdout instead of
# the mode.
perms=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null)
[ "$perms" = "600" ] || warn "$ENV_FILE с правами $perms — должно быть 600 (chmod 600 $ENV_FILE)"
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${RESTIC_REPOSITORY:?не задан в $ENV_FILE}"
: "${RESTIC_PASSWORD:?не задан в $ENV_FILE}"

log "репозиторий: $RESTIC_REPOSITORY"
[ -n "$DRY_RUN" ] && log "режим проверки, ничего не пишется"

# NOTE: the repository is initialised by hand once, never silently from here — a
# typo in the bucket name would otherwise create a new empty repo instead of
# failing.
if ! restic cat config >/dev/null 2>&1; then
  die "репозиторий недоступен или не инициализирован. Один раз: restic init"
fi

# --- backup -----------------------------------------------------------------

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

# A skipped path does not fail the backup, but it does mean something valuable
# was not saved — that has to be said now, not found in a log six months later.
if [ ${#existing[@]} -lt ${#BACKUP_PATHS[@]} ]; then
  notify "сохранено путей: ${#existing[@]} из ${#BACKUP_PATHS[@]}" "часть путей пропущена"
fi

# --- rotation ---------------------------------------------------------------
# NOTE: skipped under dry-run — without a fresh snapshot it would prune real
# history.
if [ -z "$DRY_RUN" ]; then
  log "ротация: --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY"
  if ! restic forget --prune \
    --retry-lock 10m \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY"; then
    # NOTE: its own notification, not a plain warn indistinguishable from "one
    # path skipped" — here the retention policy is not applied at all and the
    # cloud bill grows silently. It went unapplied for ten days before anyone
    # noticed.
    warn "restic forget --prune завершился с ошибкой — политика хранения НЕ применена, старые снапшоты копятся (снапшот при этом снят)"
    notify "forget --prune упал — старые версии не подрезаны, объём в репозитории растёт" "политика хранения НЕ применена"
  fi
fi

# --- summary ----------------------------------------------------------------

if [ -z "$DRY_RUN" ]; then
  # NOTE: counted by parsing JSON, not by grepping '"time"' — that field also
  # appears in nested objects and the counter lied (1 for two snapshots).
  log "снапшотов в репозитории: $(restic snapshots --json 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo '?')"
  log "готово"
fi
