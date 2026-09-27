#!/usr/bin/env bash
# Behaviour tests for stop-continue.sh.
#
# Each case works against a throwaway git repo (mktemp) and a private HOME (mktemp),
# so the per-session state under ~/.claude/.state/stop-continue never touches the real
# one and repos never collide with each other's TODO.<sid8>.md.
#
# Usage: bash tools/claude/hooks/stop-continue.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/stop-continue.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

# A private HOME confines the hook's state dir to this run.
HOME="$(mktemp -d)"; export HOME

newrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  printf '%s' "$r"
}

# mktranscript <text> -> path to a one-line JSONL transcript whose sole assistant
# record has this text. Used only by the fallback path when last_assistant_message
# is absent from the input.
mktranscript() {
  local f; f="$(mktemp)"
  jq -nc --arg t "$1" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}' > "$f"
  printf '%s' "$f"
}

# build_input <sid> <cwd> <transcript> <stop_hook_active> <msg_mode: present|absent> [msg]
build_input() {
  local sid=$1 cwd=$2 transcript=$3 active=$4 mode=$5 msg=${6:-}
  if [[ $mode == present ]]; then
    jq -nc --arg s "$sid" --arg c "$cwd" --arg t "$transcript" --argjson a "$active" --arg m "$msg" \
      '{session_id:$s, cwd:$c, transcript_path:$t, stop_hook_active:$a, last_assistant_message:$m}'
  else
    jq -nc --arg s "$sid" --arg c "$cwd" --arg t "$transcript" --argjson a "$active" \
      '{session_id:$s, cwd:$c, transcript_path:$t, stop_hook_active:$a}'
  fi
}

# run_hook <same args as build_input> -> sets OUT and ERR
run_hook() {
  local errfile; errfile="$(mktemp)"
  OUT="$(build_input "$@" | "$HOOK" 2>"$errfile")"
  ERR="$(cat "$errfile")"
  rm -f "$errfile"
}

STATE_DIR="$HOME/.claude/.state/stop-continue"

printf '\n== без TODO — тишина ==\n'
R="$(newrepo)"; SID=11111111-0000-0000-0000-000000000001
run_hook "$SID" "$R" "" false present "работаю"
[[ -z $OUT ]] && ok "нет TODO.<sid8>.md — хук молчит" || bad "нет TODO — хук молчит" "$OUT"
rm -rf "$R"

printf '\n== все пункты закрыты — тишина ==\n'
R="$(newrepo)"; SID=22222222-0000-0000-0000-000000000002
printf -- '- [x] сделано\n- [x] и это тоже\n' > "$R/TODO.22222222.md"
run_hook "$SID" "$R" "" false present "работаю"
[[ -z $OUT ]] && ok "открытых пунктов нет — хук молчит" || bad "открытых пунктов нет — хук молчит" "$OUT"
rm -rf "$R"

printf '\n== открытые пункты — блокировка с ростом счётчика до кэпа ==\n'
R="$(newrepo)"; SID=33333333-0000-0000-0000-000000000003
printf -- '- [ ] Write tests\n- [ ] Update docs\n' > "$R/TODO.33333333.md"
T="$(mktemp)"; printf 'seed\n' > "$T"
STOP_CONTINUE_MAX=3
export STOP_CONTINUE_MAX

for n in 1 2 3; do
  run_hook "$SID" "$R" "$T" false present "работаю"
  [[ $OUT == *'"decision":"block"'* ]] && ok "продолжение $n: decision=block" \
    || bad "продолжение $n: decision=block" "$OUT"
  [[ $OUT == *"Write tests; Update docs"* ]] && ok "продолжение $n: оба пункта verbatim в reason" \
    || bad "продолжение $n: пункты в reason" "$OUT"
  [[ $OUT == *"(automatic continuation ${n} of 3)"* ]] && ok "продолжение $n: счётчик в тексте" \
    || bad "продолжение $n: счётчик в тексте" "$OUT"
  # the transcript grows between continuations — otherwise this IS the stuck case
  printf 'turn %d\n' "$n" >> "$T"
done

run_hook "$SID" "$R" "$T" false present "работаю"
[[ $OUT != *'"decision"'* ]] && ok "4-е продолжение: без decision (кэп достигнут)" \
  || bad "4-е продолжение: без decision" "$OUT"
[[ $OUT == *'stopped after 3 continuation'* || $ERR == *'stopped after 3 continuation'* ]] \
  && ok "4-е продолжение: сообщение о кэпе" \
  || bad "4-е продолжение: сообщение о кэпе" "OUT=[$OUT] ERR=[$ERR]"
rm -f "$T"; rm -rf "$R"
unset STOP_CONTINUE_MAX

printf '\n== заявленный блокер — тишина даже при открытых пунктах ==\n'
R="$(newrepo)"; SID=44444444-0000-0000-0000-000000000004
printf -- '- [ ] что-то незакрытое\n' > "$R/TODO.44444444.md"
run_hook "$SID" "$R" "" false present "result: всё готово, отчёт выше"
[[ -z $OUT ]] && ok "'result:' — тишина" || bad "'result:' — тишина" "$OUT"
run_hook "$SID" "$R" "" false present "needs input: какой хост использовать?"
[[ -z $OUT ]] && ok "'needs input:' — тишина" || bad "'needs input:' — тишина" "$OUT"
run_hook "$SID" "$R" "" false present "failed: сеть недоступна"
[[ -z $OUT ]] && ok "'failed:' — тишина" || bad "'failed:' — тишина" "$OUT"
run_hook "$SID" "$R" "" false present "дальше не пойти — заблокирован конфигом"
[[ -z $OUT ]] && ok "'заблокирован' — тишина" || bad "'заблокирован' — тишина" "$OUT"
rm -rf "$R"

printf '\n== застой: те же пункты, транскрипт не изменился — тишина, не блок ==\n'
R="$(newrepo)"; SID=55555555-0000-0000-0000-000000000005
printf -- '- [ ] один и тот же пункт\n' > "$R/TODO.55555555.md"
T="$(mktemp)"; printf 'seed\n' > "$T"
run_hook "$SID" "$R" "$T" false present "работаю"
[[ $OUT == *'"decision":"block"'* ]] && ok "застой: первый вызов — блок (счётчик 1)" \
  || bad "застой: первый вызов — блок" "$OUT"
run_hook "$SID" "$R" "$T" false present "работаю"
[[ -z $OUT ]] && ok "застой: тот же файл, те же пункты — тишина без учёта кэпа" \
  || bad "застой: тишина" "$OUT"
cnt="$(jq -r '.count // "?"' "$STATE_DIR/$SID" 2>/dev/null)"
[[ $cnt == 1 ]] && ok "застой: счётчик не увеличился" || bad "застой: счётчик не увеличился" "count=$cnt"
rm -f "$T"; rm -rf "$R"

printf '\n== stop_hook_active=true — тот же путь продолжения, не самопогашение ==\n'
R="$(newrepo)"; SID=66666666-0000-0000-0000-000000000006
printf -- '- [ ] пункт\n' > "$R/TODO.66666666.md"
T="$(mktemp)"; printf 'seed\n' > "$T"
run_hook "$SID" "$R" "$T" true present "работаю"
[[ $OUT == *'"decision":"block"'* ]] && ok "stop_hook_active=true всё же продолжает (это и есть re-entry)" \
  || bad "stop_hook_active=true продолжает" "$OUT"
[[ $OUT == *"(automatic continuation 1 of 3)"* ]] && ok "stop_hook_active=true: счётчик считается как обычно" \
  || bad "stop_hook_active=true: счётчик считается" "$OUT"
rm -f "$T"; rm -rf "$R"

printf '\n== битый транскрипт без last_assistant_message — тишина, не блок ==\n'
R="$(newrepo)"; SID=77777777-0000-0000-0000-000000000007
printf -- '- [ ] пункт\n' > "$R/TODO.77777777.md"
T="$(mktemp)"; printf 'это не json\n{оборвано' > "$T"
run_hook "$SID" "$R" "$T" false absent
[[ -z $OUT ]] && ok "битый транскрипт без last_assistant_message — тишина" \
  || bad "битый транскрипт — тишина" "$OUT"
[[ ! -f "$STATE_DIR/$SID" ]] && ok "битый транскрипт: до записи состояния не дошло" \
  || bad "битый транскрипт: состояние не должно писаться"
rm -f "$T"; rm -rf "$R"

printf '\n== без last_assistant_message, но с рабочим транскриптом — фолбэк отрабатывает ==\n'
R="$(newrepo)"; SID=99999999-0000-0000-0000-000000000009
printf -- '- [ ] пункт\n' > "$R/TODO.99999999.md"
T="$(mktranscript "result: всё сделано")"
run_hook "$SID" "$R" "$T" false absent
[[ -z $OUT ]] && ok "фолбэк на транскрипт находит 'result:' — тишина" \
  || bad "фолбэк на транскрипт находит 'result:'" "$OUT"
T2="$(mktranscript "работаю дальше")"
run_hook "$SID" "$R" "$T2" false absent
[[ $OUT == *'"decision":"block"'* ]] && ok "фолбэк на транскрипт без блокера — обычный блок" \
  || bad "фолбэк на транскрипт без блокера — блок" "$OUT"
rm -f "$T" "$T2"; rm -rf "$R"

printf '\n== устаревшие файлы состояния (>7 дней) подчищаются ==\n'
mkdir -p "$STATE_DIR"
old="$STATE_DIR/oldsession"
printf '{"count":1}' > "$old"
touch -t 202001010000 "$old"
R="$(newrepo)"; SID=88888888-0000-0000-0000-000000000008
printf -- '- [ ] пункт\n' > "$R/TODO.88888888.md"
run_hook "$SID" "$R" "" false present "работаю"
[[ ! -f "$old" ]] && ok "файл состояния старше 7 дней удалён" || bad "файл состояния старше 7 дней удалён"
rm -rf "$R"

rm -rf "$HOME"
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
