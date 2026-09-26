#!/usr/bin/env bash
# Behaviour tests for pretooluse-read.sh.
#
# The hook must deny exactly one shape — a long text file read whole from a repo — and
# stay silent on everything else, or the Read tool becomes a prompt generator.
#
# Usage: bash tools/claude/hooks/pretooluse-read.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/pretooluse-read.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
T="$(mktemp -d)"
seq 1 500 > "$T/long.py"
seq 1 50  > "$T/short.py"
seq 1 500 > "$T/big.log"
seq 1 500 > "$T/Long.PNG"
mkdir -p "$T/tmp"; seq 1 500 > "$T/tmp/scratch.py"

# chk <expected: deny|pass> <file_path> <limit or ""> <description>
chk() {
  local want=$1 f=$2 limit=$3 desc=$4 got
  got=$(jq -nc --arg f "$f" --arg l "$limit" \
        '{tool_input:({file_path:$f} + (if $l != "" then {limit:($l|tonumber)} else {} end))}' \
        | "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  got=${got:-pass}
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1)); printf '  ok   %-4s  %s\n' "$got" "$desc"
  else
    fail=$((fail + 1)); printf '  FAIL ждали %s, получили %s: %s\n' "$want" "$got" "$desc"
  fi
}

chk deny "$T/long.py"   ""    'длинный файл целиком'
chk pass "$T/long.py"   "100" 'длинный файл с limit'
chk pass "$T/short.py"  ""    'короткий файл целиком'
chk pass "$T/big.log"   ""    'лог — вывод работы, не код'
chk pass "$T/Long.PNG"  ""    'картинка (регистр расширения не важен)'
chk pass "$T/nope.py"   ""    'нет такого файла — не наша забота'
chk pass "/tmp/$(basename "$T")/x.py" "" 'путь в /tmp'
chk pass "\$CLAUDE_JOB_DIR/tmp/x.py" "" 'путь в job tmp'
mkdir -p "$T/.claude/jobs/abc12345/tmp"; seq 1 500 > "$T/.claude/jobs/abc12345/tmp/helper.py"
chk pass "$T/.claude/jobs/abc12345/tmp/helper.py" "" 'job tmp литеральным путём'
READ_GUARD_MAX_LINES=40 chk deny "$T/short.py" "" 'порог настраивается через READ_GUARD_MAX_LINES'

rm -rf "$T"
printf '\nпройдено: %d, провалено: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
