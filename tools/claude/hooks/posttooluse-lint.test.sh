#!/usr/bin/env bash
# Behaviour tests for posttooluse-lint.sh.
#
# No real linter is required or trusted here: shellcheck/zsh/ruff/uvx/yamllint are not
# installed in the CI job that runs this file, so every linter the hook can call is a tiny
# stub on a curated PATH. That PATH also excludes any real linter the dev machine happens to
# have, so "missing linter" is an actual absence, not a race with what is on PATH.
#
# Usage: bash tools/claude/hooks/posttooluse-lint.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/posttooluse-lint.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

WORK="$(mktemp -d)"
SID=cccc0000-0000-0000-0000-000000000001
CWD="$WORK/cwd"; mkdir -p "$CWD"
TRANSCRIPT="$WORK/transcript.jsonl"; : > "$TRANSCRIPT"

# A curated PATH holding only what the hook itself needs (its interpreter and the few
# external commands the script body calls) — no real shellcheck/zsh/ruff/yamllint leak in
# from the dev machine, so "missing linter" means what it says.
CLEAN_BIN="$WORK/clean-bin"; mkdir -p "$CLEAN_BIN"
for b in bash sh cat head grep dirname jq; do
  p="$(command -v "$b" 2>/dev/null)" && ln -s "$p" "$CLEAN_BIN/$b"
done

# A separate bin dir for fake linters, prepended in front of CLEAN_BIN when a case wants a
# linter "present". Each stub only reacts to a marker string in the target file, so the same
# stub drives both the clean and the dirty case.
STUB_BIN="$WORK/stub-bin"; mkdir -p "$STUB_BIN"
CALL_LOG="$WORK/calls.log"

mkstub() { # mkstub <name> <fixed message>
  local name=$1 msg=$2 f="$STUB_BIN/$1"
  cat > "$f" <<EOF
#!/usr/bin/env bash
# Fake linter for posttooluse-lint.test.sh: real linters are not installed in CI, so this
# stands in and reports a fixed message only when the target file carries the marker.
echo "$name \$*" >> "$CALL_LOG"
file="\${*: -1}"
grep -q BADLINT "\$file" 2>/dev/null || exit 0
echo "$msg"
exit 1
EOF
  chmod +x "$f"
}
mkstub shellcheck "SC0000 (stub shellcheck): pretend issue"
mkstub zsh        "(stub zsh -n): pretend syntax error"
mkstub uvx        "(stub uvx ruff): pretend ruff finding"
mkstub yamllint   "(stub yamllint): pretend yaml issue"

build_input() { # <tool_name> <file_path|empty>
  local tool=$1 file=$2
  if [[ -n $file ]]; then
    jq -nc --arg s "$SID" --arg c "$CWD" --arg t "$TRANSCRIPT" --arg tn "$tool" --arg fp "$file" \
      '{session_id:$s, cwd:$c, transcript_path:$t, hook_event_name:"PostToolUse",
        tool_name:$tn, tool_input:{file_path:$fp}}'
  else
    jq -nc --arg s "$SID" --arg c "$CWD" --arg t "$TRANSCRIPT" --arg tn "$tool" \
      '{session_id:$s, cwd:$c, transcript_path:$t, hook_event_name:"PostToolUse",
        tool_name:$tn, tool_input:{command:"echo hi"}}'
  fi
}

# run_hook <tool_name> <file_path|empty> <path: clean|stubbed> -> sets OUT, RC
run_hook() {
  local tool=$1 file=$2 mode=$3 pathval
  [[ $mode == stubbed ]] && pathval="$STUB_BIN:$CLEAN_BIN" || pathval="$CLEAN_BIN"
  OUT="$(build_input "$tool" "$file" | PATH="$pathval" "$HOOK")"
  RC=$?
}

: > "$CALL_LOG"

printf '\n== нерелевантные вызовы — тишина ==\n'
run_hook Bash "" stubbed
[[ -z $OUT && $RC -eq 0 ]] && ok "нет tool_input.file_path — тишина, exit 0" \
  || bad "нет file_path — тишина" "OUT=[$OUT] RC=$RC"

f="$CWD/missing.sh"
run_hook Edit "$f" stubbed
[[ -z $OUT && $RC -eq 0 ]] && ok "file_path указывает на несуществующий файл — тишина" \
  || bad "несуществующий файл — тишина" "OUT=[$OUT] RC=$RC"

f="$CWD/notes.md"; printf 'BADLINT plain text, not a lintable type\n' > "$f"
run_hook Edit "$f" stubbed
[[ -z $OUT && $RC -eq 0 ]] && ok "тип файла (.md) не входит в список — тишина" \
  || bad "нелинтуемый тип — тишина" "OUT=[$OUT] RC=$RC"

printf '\n== shell-скрипт: чистый файл — тишина ==\n'
: > "$CALL_LOG"
f="$CWD/clean.sh"; printf '#!/usr/bin/env bash\necho ok\n' > "$f"
run_hook Write "$f" stubbed
[[ -z $OUT && $RC -eq 0 ]] && ok "чистый .sh — additionalContext отсутствует" \
  || bad "чистый .sh — тишина" "OUT=[$OUT] RC=$RC"
grep -q '^shellcheck ' "$CALL_LOG" && ok "чистый .sh — вызван именно shellcheck" \
  || bad "чистый .sh — shellcheck вызван" "лог: $(cat "$CALL_LOG")"

printf '\n== shell-скрипт с ошибкой — additionalContext и отсутствие блокировки ==\n'
f="$CWD/dirty.sh"; printf '#!/usr/bin/env bash\n# BADLINT\necho ok\n' > "$f"
run_hook Edit "$f" stubbed
[[ $OUT == *"SC0000 (stub shellcheck): pretend issue"* ]] \
  && ok "грязный .sh — сообщение линтера в additionalContext" \
  || bad "грязный .sh — сообщение линтера" "$OUT"
[[ $OUT == *"Lint results for $f:"* ]] && ok "грязный .sh — заголовок с именем файла" \
  || bad "грязный .sh — заголовок с именем файла" "$OUT"
[[ $OUT != *'"decision"'* ]] && ok "грязный .sh — нет decision, хук не блокирует" \
  || bad "грязный .sh — нет decision" "$OUT"
[[ $RC -eq 0 ]] && ok "грязный .sh — exit 0" || bad "грязный .sh — exit 0" "RC=$RC"

printf '\n== shebang zsh переключает .sh на zsh -n, а не shellcheck ==\n'
: > "$CALL_LOG"
f="$CWD/zshy.sh"; printf '#!/usr/bin/env zsh\n# BADLINT\necho ok\n' > "$f"
run_hook Edit "$f" stubbed
[[ $OUT == *"(stub zsh -n): pretend syntax error"* ]] && ok "shebang zsh — вызван zsh -n" \
  || bad "shebang zsh — вызван zsh -n" "$OUT"
[[ $OUT != *"SC0000"* ]] && ok "shebang zsh — shellcheck не подмешан в вывод" \
  || bad "shebang zsh — shellcheck не подмешан" "$OUT"
grep -q '^zsh ' "$CALL_LOG" && ok "shebang zsh — лог вызова содержит zsh" \
  || bad "shebang zsh — лог вызова содержит zsh" "лог: $(cat "$CALL_LOG")"
grep -q '^shellcheck ' "$CALL_LOG" && bad "shebang zsh — shellcheck не должен вызываться" \
  || ok "shebang zsh — shellcheck не вызывался"

printf '\n== .py без ruff, но с uvx — используется резервный путь ==\n'
f="$CWD/dirty.py"; printf '# BADLINT\nimport os\n' > "$f"
run_hook Edit "$f" stubbed
[[ $OUT == *"(stub uvx ruff): pretend ruff finding"* ]] \
  && ok "ruff недоступен — сработал запасной путь через uvx" \
  || bad "запасной путь через uvx" "$OUT"

printf '\n== .yml с ошибкой — yamllint ==\n'
f="$CWD/broken.yml"; printf '# BADLINT\nkey: value\n' > "$f"
run_hook Edit "$f" stubbed
[[ $OUT == *"(stub yamllint): pretend yaml issue"* ]] && ok ".yml с проблемой — сообщение yamllint" \
  || bad ".yml с проблемой — сообщение yamllint" "$OUT"

printf '\n== отсутствующий линтер (PATH без него) — тихая деградация ==\n'
f="$CWD/dirty2.sh"; printf '#!/usr/bin/env bash\n# BADLINT\necho ok\n' > "$f"
run_hook Edit "$f" clean
[[ -z $OUT && $RC -eq 0 ]] && ok "shellcheck отсутствует на PATH — тишина, не ошибка" \
  || bad "отсутствующий линтер — тишина" "OUT=[$OUT] RC=$RC"

rm -rf "$WORK"
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
