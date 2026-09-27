#!/usr/bin/env bash
# Behaviour tests for precompact-snapshot.sh.
#
# Every case works against a throwaway git repo (mktemp), so the snapshot never lands next
# to a real PROGRESS.<sid8>.md and never picks up the real working tree's dirty paths.
#
# Usage: bash tools/claude/hooks/precompact-snapshot.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/precompact-snapshot.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

newrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  printf '%s' "$r"
}

# build_input <sid> <cwd> <transcript|empty> <trigger>
build_input() {
  local sid=$1 cwd=$2 transcript=$3 trigger=$4
  jq -nc --arg s "$sid" --arg c "$cwd" --arg t "$transcript" --arg tr "$trigger" \
    '{session_id:$s, cwd:$c, transcript_path:$t, hook_event_name:"PreCompact", trigger:$tr}'
}

# run_hook <same args as build_input> -> sets OUT, RC
run_hook() {
  OUT="$(build_input "$@" | "$HOOK")"
  RC=$?
}

# mktranscript <assistant text> -> path to a one-line JSONL transcript with a Read tool_use
# record, so the "already reviewed" tail has something concrete to pick up.
mktranscript() {
  local f; f="$(mktemp)"
  jq -nc --arg fp "$1" \
    '{type:"assistant", message:{content:[{type:"tool_use", name:"Read", input:{file_path:$fp}}]}}' \
    > "$f"
  printf '%s' "$f"
}

printf '\n== без репозитория (cwd не git) — тишина ==\n'
NR="$(mktemp -d)"
run_hook "aaaaaaaa-0000" "$NR" "" "auto"
[[ -z $OUT && $RC -eq 0 ]] && ok "cwd вне git-репозитория — тишина, exit 0" \
  || bad "cwd вне git — тишина" "OUT=[$OUT] RC=$RC"
rm -rf "$NR"

printf '\n== снимок: ветка, незакоммиченные пути, файл создаётся ==\n'
R="$(newrepo)"
git -C "$R" checkout -q -b feat/snap
printf 'v1\n' > "$R/tracked.txt"
git -C "$R" add tracked.txt
git -C "$R" commit -q -m init >/dev/null 2>&1
printf 'v2\n' > "$R/tracked.txt"
printf 'x\n' > "$R/untracked.txt"
SID=deadbeef-0000-0000-0000-000000000001
SID8=deadbeef
run_hook "$SID" "$R" "" "manual"
[[ -z $OUT ]] && ok "хук не печатает в stdout" || bad "хук не должен печатать в stdout" "$OUT"
[[ $RC -eq 0 ]] && ok "exit 0" || bad "exit 0" "RC=$RC"
F="$R/PROGRESS.$SID8.md"
[[ -f $F ]] && ok "снимок лёг в PROGRESS.$SID8.md" || bad "PROGRESS.$SID8.md создан"
grep -q 'feat/snap' "$F" && ok "снимок содержит имя ветки" || bad "имя ветки в снимке"
grep -q 'tracked.txt' "$F" && ok "снимок содержит изменённый tracked-путь" \
  || bad "tracked.txt в снимке"
grep -q 'untracked.txt' "$F" && ok "снимок содержит untracked-путь" \
  || bad "untracked.txt в снимке"
grep -q 'trigger: manual' "$F" && ok "триггер компакта записан" || bad "триггер компакта записан"
rm -rf "$R"

printf '\n== второй компакт — снимок дописывается, не перезаписывается ==\n'
R="$(newrepo)"
git -C "$R" checkout -q -b feat/append
printf 'a\n' > "$R/a.txt"
SID=deadbeef-0000-0000-0000-000000000002
SID8=deadbeef
run_hook "$SID" "$R" "" "auto"
F="$R/PROGRESS.$SID8.md"
first_lines="$(wc -l < "$F")"
printf 'b\n' > "$R/b.txt"
run_hook "$SID" "$R" "" "auto"
second_lines="$(wc -l < "$F")"
[[ "$second_lines" -gt "$first_lines" ]] && ok "второй компакт дописал файл (строк выросло)" \
  || bad "второй компакт дописал файл" "было $first_lines, стало $second_lines"
[[ "$(grep -c '^# PROGRESS' "$F")" -eq 1 ]] && ok "заголовок # PROGRESS не задвоился" \
  || bad "заголовок # PROGRESS не задвоился"
grep -q 'a.txt' "$F" && grep -q 'b.txt' "$F" && ok "оба снимка (a.txt и b.txt) присутствуют" \
  || bad "оба снимка присутствуют"
rm -rf "$R"

printf '\n== чистое рабочее дерево — снимок без списка путей ==\n'
R="$(newrepo)"
printf 'x\n' > "$R/x.txt"
git -C "$R" add x.txt
git -C "$R" commit -q -m init >/dev/null 2>&1
SID=cafef00d-0000-0000-0000-000000000003
run_hook "$SID" "$R" "" "auto"
F="$R/PROGRESS.cafef00d.md"
grep -q 'рабочее дерево чистое' "$F" && ok "чистое дерево отражено в тексте" \
  || bad "чистое дерево отражено в тексте"
rm -rf "$R"

printf '\n== хвост транскрипта: просмотренные файлы попадают в снимок ==\n'
R="$(newrepo)"
SID=1234abcd-0000-0000-0000-000000000004
T="$(mktranscript "$R/reviewed.txt")"
run_hook "$SID" "$R" "$T" "auto"
F="$R/PROGRESS.1234abcd.md"
grep -q 'Read '"$R/reviewed.txt" "$F" \
  && ok "прочитанный в транскрипте файл попал в 'уже просмотрено'" \
  || bad "просмотренный файл в снимке"
grep -q 'не перечитывать без причины' "$F" && ok "пояснение про 'не перечитывать без причины' на месте" \
  || bad "пояснение на месте"
rm -f "$T"; rm -rf "$R"

printf '\n== session_id пуст — снимок в общий PROGRESS.md ==\n'
R="$(newrepo)"
run_hook "" "$R" "" "auto"
[[ -f "$R/PROGRESS.md" ]] && ok "без session_id снимок лёг в общий PROGRESS.md" \
  || bad "без session_id — PROGRESS.md"
rm -rf "$R"

printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
