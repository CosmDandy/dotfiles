#!/usr/bin/env bash
set -uo pipefail

# Backup watchdog: checks how fresh the newest snapshot is and verifies repository
# integrity once a week.
#
# NOTE: separate from backup.sh because that script can complain when it FAILED but not
# when it was never started — and that is the typical failure: broken credentials, an
# unloaded launchd agent, an empty Object Storage account. From the outside everything
# looks fine right up to the day the backup is needed.
#
# Usage: ./backup-check.sh [--quiet]
#   --quiet  no notification when all is well (for launchd)

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin"

ENV_FILE="${RESTIC_ENV_FILE:-$HOME/.config/restic/env}"
# The backup is daily, so two days is a miss rather than "the mac was off last night".
MAX_AGE_DAYS="${BACKUP_MAX_AGE_DAYS:-2}"
# A full integrity check reads data back from the cloud, hence not every day.
CHECK_EVERY_DAYS="${BACKUP_CHECK_EVERY_DAYS:-7}"
STAMP="$HOME/.cache/restic-last-check"
QUIET=""
[ "${1:-}" = "--quiet" ] && QUIET=1

log() { echo "[backup-check] $*"; }

notify() {
  osascript -e "display notification \"$1\" with title \"Бэкап\" subtitle \"$2\"" \
    >/dev/null 2>&1 || true
}

fail() {
  log "ОШИБКА: $*"
  notify "$*" "проверка бэкапа"
  exit 1
}

[ -f "$ENV_FILE" ] || fail "нет файла доступов $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"
command -v restic >/dev/null || fail "restic не найден в PATH"

# --- freshness of the latest snapshot ----------------------------------------

snapshots_json=$(restic snapshots --json --latest 1 2>/dev/null)
[ -n "$snapshots_json" ] || fail "репозиторий недоступен — проверь доступы и сеть"

age_hours=$(SNAP="$snapshots_json" python3 - <<'PY'
import json, os, sys
from datetime import datetime, timezone
try:
    snaps = json.loads(os.environ["SNAP"])
except json.JSONDecodeError:
    sys.exit(1)
if not snaps:
    print("-1")
    sys.exit(0)
# restic returns the time with a timezone and microseconds
t = snaps[-1]["time"].split(".")[0]
tz = snaps[-1]["time"][-6:] if snaps[-1]["time"][-6] in "+-" else "+00:00"
dt = datetime.fromisoformat(t + tz)
print(int((datetime.now(timezone.utc) - dt).total_seconds() // 3600))
PY
) || fail "не смог разобрать ответ restic"

if [ "$age_hours" = "-1" ]; then
  fail "в репозитории нет ни одного снапшота"
fi

age_days=$((age_hours / 24))
log "последний снапшот: $age_hours ч назад"

if [ "$age_days" -ge "$MAX_AGE_DAYS" ]; then
  fail "последний снапшот $age_days дн. назад — бэкап не выполняется"
fi

# --- periodic integrity check ------------------------------------------------

need_check=1
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed_days=$(( (now - last) / 86400 ))
  [ "$elapsed_days" -lt "$CHECK_EVERY_DAYS" ] && need_check=""
fi

if [ -n "$need_check" ]; then
  log "проверяю целостность репозитория"
  # NOTE: the verdict comes from the EXIT CODE, and the three causes are told apart by the
  # error text. Deciding by grepping for "no errors were found" made a lock, an unreachable
  # repository and real corruption produce the same "repository is damaged" alert — the one
  # alert you act on by restoring something that was fine.
  check_output=$(restic check --read-data-subset=2% --retry-lock 10m 2>&1)
  check_exit=$?
  if [ "$check_exit" -eq 0 ]; then
    mkdir -p "$(dirname "$STAMP")"
    date +%s > "$STAMP"
    log "целостность в порядке"
  elif echo "$check_output" | grep -qE "repository is already locked|unable to create.*lock"; then
    # --retry-lock already retried and still gave up, so a live process holds the lock
    # rather than a leftover from a previous run.
    fail "репозиторий залочен — restic check не смог взять лок даже после ретраев (10м). Проверь, не идёт ли сейчас другой restic; если процесс мёртв: restic unlock"
  elif echo "$check_output" | grep -qiE "no such host|connection refused|dial tcp|TLS handshake|context deadline exceeded|401|403|InvalidAccessKeyId|SignatureDoesNotMatch|AccessDenied|wrong password|unable to open (repository|config)"; then
    fail "репозиторий недоступен — проблема с сетью или доступами, не повреждение: $(echo "$check_output" | tail -3)"
  else
    fail "restic check нашёл ошибки — репозиторий повреждён: $(echo "$check_output" | tail -3)"
  fi
fi

[ -z "$QUIET" ] && notify "снапшот свежий ($age_hours ч), ошибок нет" "проверка пройдена"
log "готово"
