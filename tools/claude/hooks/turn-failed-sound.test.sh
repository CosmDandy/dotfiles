#!/usr/bin/env bash
# Behaviour tests for turn-failed-sound.sh.
#
# The hook itself is /bin/sh and gates on the hardcoded macOS path
# /System/Library/Sounds/Basso.aiff — real on this dev machine, never present on the
# ubuntu-24.04 CI runner. So the "player invoked" case only runs where that file exists and
# is SKIPped otherwise (same convention as the gitleaks-absent skips in
# pretooluse-guard.test.sh); the "silent" and "always exits 0" assertions hold on both, since
# a missing sound file and a missing player both take the hook down the same quiet path.
#
# The real /usr/bin/afplay is never used here — even the "present" case runs a stub, so
# these tests never make an audible sound on the developer's machine.
#
# Usage: bash tools/claude/hooks/turn-failed-sound.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/turn-failed-sound.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

SOUND=/System/Library/Sounds/Basso.aiff
WORK="$(mktemp -d)"

# A StopFailure-shaped payload. The hook reads none of it (see its own comment: it only
# reacts to being invoked at all), but it is fed one anyway for realism.
INPUT="$(jq -nc \
  '{session_id:"eeee0000-0000-0000-0000-000000000001",
    cwd:"/tmp", transcript_path:"/tmp/transcript.jsonl", hook_event_name:"StopFailure"}')"

# A curated PATH with no afplay at all — used both to simulate "player absent" and as the
# base for the "player present" case's own bin dir.
CLEAN_BIN="$WORK/clean-bin"; mkdir -p "$CLEAN_BIN"
for b in bash sh cat; do
  p="$(command -v "$b" 2>/dev/null)" && ln -s "$p" "$CLEAN_BIN/$b"
done

printf '\n== плеер недоступен на PATH — тишина, exit 0 ==\n'
OUT="$(printf '%s' "$INPUT" | PATH="$CLEAN_BIN" "$HOOK")"
RC=$?
[[ $RC -eq 0 ]] && ok "afplay недоступен — exit 0" || bad "afplay недоступен — exit 0" "RC=$RC"
[[ -z $OUT ]] && ok "afplay недоступен — нет stdout" || bad "afplay недоступен — нет stdout" "$OUT"

printf '\n== звуковой файл присутствует — плеер вызывается с ожидаемым путём ==\n'
if [[ -f $SOUND ]]; then
  STUB_BIN="$WORK/stub-bin"; mkdir -p "$STUB_BIN"
  CALL_LOG="$WORK/calls.log"; : > "$CALL_LOG"
  cat > "$STUB_BIN/afplay" <<EOF
#!/bin/sh
# Records its own argv instead of touching real audio hardware.
echo "\$*" >> "$CALL_LOG"
EOF
  chmod +x "$STUB_BIN/afplay"
  export CALL_LOG

  OUT="$(printf '%s' "$INPUT" | PATH="$STUB_BIN:$CLEAN_BIN" "$HOOK")"
  RC=$?
  [[ $RC -eq 0 ]] && ok "плеер есть — exit 0" || bad "плеер есть — exit 0" "RC=$RC"
  [[ -z $OUT ]] && ok "плеер есть — нет stdout" || bad "плеер есть — нет stdout" "$OUT"

  # The player is launched with `&` (fire-and-forget) — poll briefly instead of a fixed
  # sleep, since the background job's write can lag the hook's own exit by a beat.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s $CALL_LOG ]] && break
    sleep 0.1
  done
  [[ -s $CALL_LOG ]] && ok "стаб afplay был вызван" || bad "стаб afplay был вызван" "лог пуст"
  grep -qF "$SOUND" "$CALL_LOG" 2>/dev/null && ok "вызван с ожидаемым путём к звуку ($SOUND)" \
    || bad "вызван с ожидаемым путём" "лог: $(cat "$CALL_LOG" 2>/dev/null)"
else
  printf '  SKIP  %s отсутствует на этой платформе — случай "плеер вызван" непроверяем\n' "$SOUND"
fi

rm -rf "$WORK"
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
