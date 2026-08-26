#!/usr/bin/env bash
# Re-transcribe the last Spokenly recording and paste it into the current input field.
#
# An accidental Escape during dictation cancels the transcription, but Spokenly has already
# saved the .wav in History. Recovering it by hand means: open the window, History,
# "transcribe again", copy, come back, paste. This does the same on one key.
#
# Spokenly runs a local MCP server (plain HTTP + JSON-RPC) with a transcribe_file tool.
# NOTE: the port lives in mcp-bridge.sh, which the app rewrites for the current port — it
# cannot be hardcoded.
#
# Bind it from anything that can run a file (Leader Key, a Raycast script command, skhd).
# NOTE: the launching process needs Accessibility permission, or the paste silently does
# nothing — the text still lands in the clipboard.
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

# History is split into YYYY-MM-DD directories.
# NOTE: only the two newest are scanned — there are thousands of recordings taking
# gigabytes, and the second day is needed only when today's directory is still empty
# (the recording happened before midnight).
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

# NOTE: the pause lets focus return to the input field from the launcher overlay that
# started the script — without it Cmd+V sometimes lands in the launcher window itself.
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "v" using command down' >/dev/null 2>&1 \
  || notify "Текст в буфере, но вставить не смог — нет прав Accessibility"
