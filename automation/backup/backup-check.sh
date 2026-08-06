#!/usr/bin/env bash
set -uo pipefail

# Сторож бэкапа: смотрит, насколько свеж последний снапшот, и раз в неделю
# проверяет целостность репозитория.
#
# Зачем отдельно от backup.sh. Тот умеет пожаловаться, когда упал, но не когда
# его вообще не запустили — а это и есть типичный отказ: сломались доступы,
# выгрузился launchd-агент, кончились деньги на Object Storage. Снаружи всё
# выглядит нормально ровно до дня, когда бэкап понадобился.
#
# Запуск: ./backup-check.sh [--quiet]
#   --quiet  не слать уведомление, когда всё хорошо (для launchd)

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin"

ENV_FILE="${RESTIC_ENV_FILE:-$HOME/.config/restic/env}"
# Порог тревоги. Бэкап ежедневный, так что двое суток — это уже пропуск, а не
# «мак был выключен вечером».
MAX_AGE_DAYS="${BACKUP_MAX_AGE_DAYS:-2}"
# Полная проверка целостности читает данные из облака, поэтому не каждый день.
CHECK_EVERY_DAYS="${BACKUP_CHECK_EVERY_DAYS:-7}"
STAMP="$HOME/.cache/restic-last-check"
QUIET=""
[ "${1:-}" = "--quiet" ] && QUIET=1

log() { echo "[backup-check] $*"; }

notify() {
  osascript -e "display notification \"$1\" with title \"Бэкап\" subtitle \"$2\" sound name \"Basso\"" \
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

# --- свежесть последнего снапшота -------------------------------------------

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
# restic отдаёт время с таймзоной и микросекундами
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

# --- периодическая проверка целостности -------------------------------------

need_check=1
if [ -f "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed_days=$(( (now - last) / 86400 ))
  [ "$elapsed_days" -lt "$CHECK_EVERY_DAYS" ] && need_check=""
fi

if [ -n "$need_check" ]; then
  log "проверяю целостность репозитория"
  # Раньше решение принималось по grep "no errors were found" в выводе — и лок,
  # и недоступность репозитория, и реальное повреждение давали одно и то же
  # сообщение «репозиторий повреждён», что будило человека чинить несуществующую
  # поломку (см. инцидент 2026-07-26: check просто не смог взять лок). Теперь
  # решение — по коду возврата, а причина отказа различается по тексту ошибки.
  check_output=$(restic check --read-data-subset=2% --retry-lock 10m 2>&1)
  check_exit=$?
  if [ "$check_exit" -eq 0 ]; then
    mkdir -p "$(dirname "$STAMP")"
    date +%s > "$STAMP"
    log "целостность в порядке"
  elif echo "$check_output" | grep -qE "repository is already locked|unable to create.*lock"; then
    # --retry-lock 10m уже отретраил взятие лока и всё равно сдался — значит
    # лок держит живой процесс, а не мусор от прошлого запуска.
    fail "репозиторий залочен — restic check не смог взять лок даже после ретраев (10м). Проверь, не идёт ли сейчас другой restic; если процесс мёртв: restic unlock"
  elif echo "$check_output" | grep -qiE "no such host|connection refused|dial tcp|TLS handshake|context deadline exceeded|401|403|InvalidAccessKeyId|SignatureDoesNotMatch|AccessDenied|wrong password|unable to open (repository|config)"; then
    fail "репозиторий недоступен — проблема с сетью или доступами, не повреждение: $(echo "$check_output" | tail -3)"
  else
    fail "restic check нашёл ошибки — репозиторий повреждён: $(echo "$check_output" | tail -3)"
  fi
fi

[ -z "$QUIET" ] && notify "снапшот свежий ($age_hours ч), ошибок нет" "проверка пройдена"
log "готово"
