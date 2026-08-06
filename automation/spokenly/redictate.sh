#!/usr/bin/env bash
# Перетранскрибировать последнюю запись Spokenly и вставить её в текущее поле ввода.
#
# Зачем: случайный Escape во время диктовки отменяет транскрипцию, но сам .wav
# Spokenly уже сохранил в History. Восстановление через интерфейс — открыть окно,
# История, «транскрибировать заново», скопировать, вернуться, вставить. Скрипт
# делает то же самое одной кнопкой.
#
# Как это работает: у Spokenly есть локальный MCP-сервер (обычный HTTP + JSON-RPC),
# и в нём инструмент transcribe_file. Порт живёт не в настройках, а в скрипте-мосте
# mcp-bridge.sh, который приложение переписывает под текущий порт — оттуда и читаем,
# зашивать число нельзя.
#
# Биндить самому: Leader Key (type "command"), Raycast script command, skhd — что угодно,
# что умеет запустить файл. Процессу, который запускает скрипт, нужен доступ к
# «Универсальному доступу» (Accessibility) — иначе вставка молча не сработает,
# а текст всё равно останется в буфере.
set -uo pipefail

SUPPORT="$HOME/Library/Application Support/Spokenly"
HIST="$SUPPORT/History"
BRIDGE="$SUPPORT/mcp-bridge.sh"

notify() {
  osascript -e "display notification \"$1\" with title \"Spokenly\"" >/dev/null 2>&1
}

die() {
  notify "$1"
  echo "$1" >&2
  exit 1
}

[[ -f "$BRIDGE" ]] || die "Не найден mcp-bridge.sh — MCP-сервер Spokenly не включён"
port="$(awk -F= '/^PORT=/{print $2; exit}' "$BRIDGE")"
[[ -n "$port" ]] || die "В mcp-bridge.sh нет строки PORT="

# История разложена по каталогам YYYY-MM-DD. Берём два последних, а не всю папку:
# записей тысячи и она весит гигабайты, а «последняя» всегда в свежем каталоге —
# два нужны только на случай, когда сегодняшний ещё пуст (запись была до полуночи).
days=()
while IFS= read -r d; do
  days+=("$d")
done < <(find "$HIST" -maxdepth 1 -type d -name '2[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 2>/dev/null \
  | sort -r | head -2)
[[ ${#days[@]} -gt 0 ]] || die "В History нет ни одного дня записей"

wav="$(find "${days[@]}" -maxdepth 1 -name '*.wav' -exec stat -f '%m %N' {} + 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2-)"
[[ -n "$wav" ]] || die "Не нашёл ни одной записи .wav"

req="$(jq -nc --arg p "$wav" \
  '{jsonrpc:"2.0",id:1,method:"tools/call",
    params:{name:"transcribe_file",arguments:{file_path:$p,format:"text"}}}')"

resp="$(curl -s --max-time 300 -X POST "http://localhost:${port}" \
  -H 'Content-Type: application/json' -d "$req")"
[[ -n "$resp" ]] || die "MCP-сервер Spokenly не ответил на порту ${port} — приложение запущено?"

text="$(printf '%s' "$resp" | jq -r '.result.content[0].text // empty')"
if [[ -z "$text" ]]; then
  err="$(printf '%s' "$resp" | jq -r '.error.message // "пустой ответ"')"
  die "Транскрипция не удалась: ${err}"
fi

printf '%s' "$text" | pbcopy

# Пауза — чтобы фокус успел вернуться в поле ввода из оверлея лаунчера, который
# запустил скрипт. Без неё Cmd+V иногда прилетает ещё в само окно лаунчера.
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "v" using command down' >/dev/null 2>&1 \
  || notify "Текст в буфере, но вставить не смог — нет прав Accessibility"
