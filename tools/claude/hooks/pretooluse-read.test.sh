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
# NOTE: not mktemp's default location — on macOS that is /var/folders, which the hook
# treats as scratch, and every "deny" case would pass for the wrong reason.
T="$(mktemp -d "$(dirname -- "$HOOK")/.read-guard-test.XXXXXX")"
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
got=$(jq -nc --arg f "$T/long.py" '{tool_input:{file_path:$f,offset:380}}' | "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ -z $got ]]; then pass=$((pass + 1)); printf '  ok   pass  %s\n' 'длинный файл с одним offset'
else fail=$((fail + 1)); printf '  FAIL ждали pass, получили %s: %s\n' "$got" 'длинный файл с одним offset'; fi
mkdir -p "$T/tool-results"; seq 1 500 > "$T/tool-results/bg6eva099.txt"
chk pass "$T/tool-results/bg6eva099.txt" "" 'переполненный вывод Bash, который харнес велит прочитать'
seq 1 500 > "$T/notes.txt"
chk pass "$T/notes.txt" "" '.txt — как в guard'
chk pass "$T/short.py"  ""    'короткий файл целиком'
chk pass "$T/big.log"   ""    'лог — вывод работы, не код'
chk pass "$T/Long.PNG"  ""    'картинка (регистр расширения не важен)'
chk pass "$T/nope.py"   ""    'нет такого файла — не наша забота'
# NOTE: the path exemptions are checked AFTER `-f`, so each case needs a real long
# file at the exempt path — a missing file passes for the wrong reason. Hence the
# literal /tmp directory (mktemp on macOS lands in /var/folders, which is not exempt),
# and no `$CLAUDE_JOB_DIR` literal: the harness always hands the hook an expanded path,
# so only the `.claude/jobs/<id>/tmp` form is reachable in practice.
TMPX="/tmp/read-guard-test.$$"; mkdir -p "$TMPX"; seq 1 500 > "$TMPX/x.py"
chk pass "$TMPX/x.py" "" 'длинный файл в /tmp'
mkdir -p "$T/.claude/jobs/abc12345/tmp"; seq 1 500 > "$T/.claude/jobs/abc12345/tmp/helper.py"
chk pass "$T/.claude/jobs/abc12345/tmp/helper.py" "" 'длинный файл в job tmp (раскрытый путь)'
chk deny "$T/long.py" "" 'тот же размер вне scratch — deny (контроль исключений)'
rm -rf "$TMPX"
READ_GUARD_MAX_LINES=40 chk deny "$T/short.py" "" 'порог настраивается через READ_GUARD_MAX_LINES'

rm -rf "$T"
printf '\nпройдено: %d, провалено: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
