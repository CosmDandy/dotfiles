#!/usr/bin/env bash
# overnight.sh — headless-запуск Claude Code для отложенной («ночной») работы.
#
# ЧЕРНОВИК механизма (см. README.md). НЕ ТЕСТИРОВАН — правь под себя перед боевым запуском.
#
# Идея: cron/systemd-timer дёргает этот скрипт в окно после сброса лимитов токенов.
# Скрипт берёт задачи из очереди (*.task.md), для каждой запускает `claude -p` в
# неинтерактивном режиме на ВЫДЕЛЕННОЙ ветке, пишет лог и переносит сделанное в done/.
#
# Главные рейлы: никогда не работать прямо в master/main; белый список инструментов;
# бэкофф при rate-limit; flock против параллельных запусков.

set -euo pipefail

# ── Конфиг (переопределяется переменными окружения) ──────────────────────────
REPO="${OVERNIGHT_REPO:-$HOME/dotfiles}"
MODEL="${OVERNIGHT_MODEL:-opus}"
QUEUE_DIR="${OVERNIGHT_QUEUE:-$REPO/tools/claude/overnight/queue}"
LOG_DIR="${OVERNIGHT_LOG_DIR:-$HOME/.local/state/overnight}"
BASE_BRANCH="${OVERNIGHT_BASE:-master}"
LOCK_FILE="${OVERNIGHT_LOCK:-$LOG_DIR/.lock}"
# Белый список инструментов: всё, что вне его, заблокировано даже при skip-permissions.
ALLOWED_TOOLS="${OVERNIGHT_TOOLS:-Edit Write Read Bash Grep Glob Task TodoWrite WebSearch WebFetch}"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

usage() {
  cat <<'EOF'
overnight.sh — headless Claude Code runner.

  overnight.sh                 обработать все *.task.md из очереди
  overnight.sh --once FILE     выполнить один файл-задачу и выйти
  overnight.sh -h | --help     эта справка

Env: OVERNIGHT_REPO, OVERNIGHT_MODEL, OVERNIGHT_QUEUE, OVERNIGHT_LOG_DIR,
     OVERNIGHT_BASE, OVERNIGHT_TOOLS, OVERNIGHT_LOCK
EOF
}

# ── Никогда не работать прямо в master/main ──────────────────────────────────
ensure_safe_branch() {
  local cur
  cur=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
  if [ "$cur" = "master" ] || [ "$cur" = "main" ]; then
    local branch
    branch="overnight/$(date +%Y%m%d-%H%M%S)"
    log "На '$cur' работать запрещено — создаю ветку '$branch' от '$BASE_BRANCH'"
    git -C "$REPO" switch -c "$branch" "$BASE_BRANCH"
  else
    log "Рабочая ветка: '$cur'"
  fi
}

# ── Один прогон по файлу-задаче ──────────────────────────────────────────────
run_one() {
  local task_file="$1"
  local ts log_file
  ts=$(date +%Y%m%d-%H%M%S)
  log_file="$LOG_DIR/$(basename "$task_file" .md)-$ts.log"
  log "▶ задача: $task_file → лог: $log_file"

  local sys
  sys=$(cat <<'EOF'
Ты работаешь АВТОНОМНО ночью, пользователь спит. Жёсткие правила:
1. НИКОГДА не пушь и не мёржи в master/main. Работай только в текущей (выделенной) ветке.
2. Делай АТОМАРНЫЕ коммиты — каждый рабочий, conventional commits, и пушь каждый коммит.
3. Никаких деструктивных операций: rm -rf вне рабочей копии, reset --hard, force-push,
   правок вне репозитория проекта.
4. Если что-то непонятно/рискованно — НЕ делай, зафиксируй вопрос в финальном отчёте.
5. В конце дай краткий отчёт: что сделано, список коммитов, что осталось/под вопросом.
EOF
)

  cd "$REPO"
  local attempt=1 max=3
  while [ "$attempt" -le "$max" ]; do
    if claude -p "$(cat "$task_file")" \
      --model "$MODEL" \
      --append-system-prompt "$sys" \
      --dangerously-skip-permissions \
      --allowedTools "$ALLOWED_TOOLS" \
      --add-dir "$REPO" \
      --output-format stream-json --verbose \
      >>"$log_file" 2>&1; then
      log "✔ завершено: $task_file"
      return 0
    fi
    log "⚠ попытка $attempt/$max упала (возможно, лимит токенов) — бэкофф"
    sleep "$(( attempt * 300 ))"
    attempt=$(( attempt + 1 ))
  done
  log "✖ не удалось после $max попыток: $task_file"
  return 1
}

main() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
  fi

  mkdir -p "$LOG_DIR"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "Уже выполняется (lock занят) — выхожу"
    exit 0
  fi

  command -v claude >/dev/null 2>&1 || { log "ОШИБКА: 'claude' не найден в PATH"; exit 1; }
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { log "ОШИБКА: '$REPO' не git-репозиторий"; exit 1; }

  ensure_safe_branch

  if [ "${1:-}" = "--once" ]; then
    [ -n "${2:-}" ] || { log "ОШИБКА: --once требует путь к файлу"; exit 1; }
    run_one "$2"
    exit $?
  fi

  shopt -s nullglob
  local found=0 f
  for f in "$QUEUE_DIR"/*.task.md; do
    found=1
    if run_one "$f"; then
      mkdir -p "$QUEUE_DIR/done"
      mv "$f" "$QUEUE_DIR/done/$(basename "$f").$(date +%Y%m%d-%H%M%S)"
    fi
  done
  [ "$found" -eq 0 ] && log "Очередь пуста: $QUEUE_DIR"
}

main "$@"
