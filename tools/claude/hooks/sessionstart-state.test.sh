#!/usr/bin/env bash
# Behaviour tests for sessionstart-state.sh.
#
# The hook reads several fixed $HOME paths (tools/claude/custom, ~/.claude/projects,
# ~/.claude/.knowledge-last-harvest), so every case runs under a private HOME from mktemp —
# otherwise it would report on this machine's real submodule and real harvest history.
# Anything the hook reaches through .cwd is a throwaway git repo from mktemp too.
#
# Usage: bash tools/claude/hooks/sessionstart-state.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sessionstart-state.sh"
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

# ts_for <epoch> -> a touch -t timestamp for that epoch, BSD or GNU date.
ts_for() {
  date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S
}

# run_hook <sid> <source> <cwd> -> sets OUT (raw stdout) and CTX (additionalContext, or "").
# NOTE: the hook derives its repo root from `git rev-parse --show-toplevel` with no -C, i.e.
# from its OWN process cwd — the JSON .cwd field is only used for the worktree "where" line.
# So the test must actually cd into $cwd, not just report it in the JSON.
run_hook() {
  local sid=$1 src=$2 cwd=$3
  OUT="$(jq -nc --arg s "$sid" --arg src "$src" --arg c "$cwd" \
    '{session_id:$s, source:$src, cwd:$c, hook_event_name:"SessionStart"}' | (cd "$cwd" && "$HOOK"))"
  if [[ -n $OUT ]]; then
    CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  else
    CTX=""
  fi
}

printf '\n== ничего не сообщить — хук молчит ==\n'
HOME="$(mktemp -d)"; export HOME
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ -z $OUT ]] && ok "нет sid, submodule, PROGRESS.md, harvest-истории — тишина" \
  || bad "тишина при отсутствии данных" "$OUT"
rm -rf "$R" "$HOME"

printf '\n== структура вывода: JSON с hookSpecificOutput.additionalContext ==\n'
HOME="$(mktemp -d)"; export HOME
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n- пункт\n' > "$R/PROGRESS.md"
SID=11112222-0000-0000-0000-000000000001
run_hook "$SID" "startup" "$R"
[[ -n $OUT ]] && ok "есть что сообщить — вывод не пуст" || bad "вывод не пуст"
event="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // ""')"
[[ $event == SessionStart ]] && ok "hookEventName == SessionStart" \
  || bad "hookEventName == SessionStart" "получили [$event]"
[[ -n $CTX ]] && ok "additionalContext не пуст" || bad "additionalContext не пуст"
rm -rf "$R" "$HOME"

printf '\n== Session id: именует ОСНОВНОЙ checkout, даже запущенный из воркетри ==\n'
HOME="$(mktemp -d)"; export HOME
R="$(newrepo)"
# mktemp on macOS returns a /var/... path that is itself a symlink into /private/var/...;
# git resolves symlinks, so comparing against the raw mktemp path would never match.
R="$(cd "$R" && pwd -P)"
SID=33334444-0000-0000-0000-000000000002
SID8=33334444
git -C "$R" worktree add -q -b wt-start "$R/.claude/worktrees/wt-start" 2>/dev/null
if [[ -d "$R/.claude/worktrees/wt-start" ]]; then
  mkdir -p "$R/.claude/worktrees/wt-start/sub"
  run_hook "$SID" "startup" "$R/.claude/worktrees/wt-start/sub"
  [[ $CTX == *"Session id: ${SID8}."* ]] && ok "строка Session id присутствует" \
    || bad "строка Session id присутствует" "$CTX"
  [[ $CTX == *" in ${R}/"* ]] && ok "названо именно основное дерево ($R), а не воркетри" \
    || bad "названо основное дерево" "$CTX"
else
  printf '  SKIP  git worktree недоступен\n'
fi
rm -rf "$R" "$HOME"

printf '\n== грязный tools/claude/custom — предупреждение о сабмодуле ==\n'
HOME="$(mktemp -d)"; export HOME
SUB="$HOME/.dotfiles/tools/claude/custom"
mkdir -p "$SUB"
git -C "$SUB" init -q
git -C "$SUB" config user.email t@example.invalid
git -C "$SUB" config user.name t
printf 'v1\n' > "$SUB/f.txt"
git -C "$SUB" add f.txt
git -C "$SUB" commit -q -m init >/dev/null 2>&1
printf 'v2\n' > "$SUB/f.txt"
printf 'new\n' > "$SUB/g.txt"
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ $CTX == *"tools/claude/custom"* && $CTX == *"uncommitted path"* ]] \
  && ok "грязный сабмодуль — предупреждение присутствует" \
  || bad "предупреждение о сабмодуле" "$CTX"
[[ $CTX == *"2 uncommitted"* ]] && ok "число незакоммиченных путей верное (2)" \
  || bad "число незакоммиченных путей" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== чистый tools/claude/custom — предупреждения нет ==\n'
HOME="$(mktemp -d)"; export HOME
SUB="$HOME/.dotfiles/tools/claude/custom"
mkdir -p "$SUB"
git -C "$SUB" init -q
git -C "$SUB" config user.email t@example.invalid
git -C "$SUB" config user.name t
printf 'v1\n' > "$SUB/f.txt"
git -C "$SUB" add f.txt
git -C "$SUB" commit -q -m init >/dev/null 2>&1
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n- пункт\n' > "$R/PROGRESS.md"
run_hook "" "startup" "$R"
[[ $CTX != *"tools/claude/custom"* ]] && ok "чистый сабмодуль — предупреждения нет" \
  || bad "предупреждения о сабмодуле не должно быть" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== PROGRESS.md ## Next и чужие фрагменты попадают в вывод, свои — нет ==\n'
HOME="$(mktemp -d)"; export HOME
R="$(newrepo)"
R="$(cd "$R" && pwd -P)"  # match the physical path git rev-parse --show-toplevel returns
SID=55556666-0000-0000-0000-000000000003
SID8=55556666
printf '# PROGRESS\n\n## Next\n- перенесённая задача\n' > "$R/PROGRESS.md"
printf 'чужой фрагмент\n' > "$R/PROGRESS.ffffffff.md"
printf -- '- [ ] чужой todo\n' > "$R/TODO.ffffffff.md"
printf 'свой фрагмент\n' > "$R/PROGRESS.${SID8}.md"
run_hook "$SID" "startup" "$R"
[[ $CTX == *"перенесённая задача"* ]] && ok "## Next из PROGRESS.md отдан" \
  || bad "## Next из PROGRESS.md отдан" "$CTX"
[[ $CTX == *"PROGRESS.ffffffff.md"* ]] && ok "чужой PROGRESS-фрагмент назван" \
  || bad "чужой PROGRESS-фрагмент назван" "$CTX"
[[ $CTX == *"TODO.ffffffff.md"* ]] && ok "чужой TODO назван" || bad "чужой TODO назван" "$CTX"
# The bare filename "PROGRESS.<sid8>.md" legitimately appears in the "Session id:" line
# above; only the absolute path in the "other sessions" listing would mean it leaked there.
[[ $CTX != *"$R/PROGRESS.${SID8}.md"* ]] && ok "собственный фрагмент не попал в список чужих" \
  || bad "собственный фрагмент не в списке чужих" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== source=compact: хвост собственного фрагмента отдаётся, source=startup — нет ==\n'
HOME="$(mktemp -d)"; export HOME
R="$(newrepo)"
SID=77778888-0000-0000-0000-000000000004
SID8=77778888
printf '# PROGRESS\n\nнаходка до компакта\n' > "$R/PROGRESS.${SID8}.md"
run_hook "$SID" "compact" "$R"
[[ $CTX == *"находка до компакта"* ]] && ok "compact: хвост фрагмента отдан" \
  || bad "compact: хвост фрагмента отдан" "$CTX"
[[ $CTX == *"схлопнулся"* ]] && ok "compact: пояснение про продолжение работы есть" \
  || bad "compact: пояснение есть" "$CTX"
run_hook "$SID" "startup" "$R"
[[ $CTX != *"находка до компакта"* ]] && ok "startup: хвоста фрагмента нет" \
  || bad "startup: хвоста быть не должно" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== knowledge harvest: маркера нет — "never" при достаточном числе сессий ==\n'
HOME="$(mktemp -d)"; export HOME
mkdir -p "$HOME/.claude/projects/proj1"
for i in 1 2 3; do
  dd if=/dev/zero of="$HOME/.claude/projects/proj1/s$i.jsonl" bs=1024 count=600 status=none
done
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ $CTX == *"Last /knowledge harvest: never"* ]] && ok "маркер отсутствует — 'never'" \
  || bad "'never' при отсутствии маркера" "$CTX"
[[ $CTX == *"3 substantial sessions"* ]] && ok "число сессий с момента (никогда не было) верное" \
  || bad "число сессий верное" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== knowledge harvest: маркер 5 дней назад, 3 новых сессии — "5d ago" ==\n'
HOME="$(mktemp -d)"; export HOME
mkdir -p "$HOME/.claude"
marker="$HOME/.claude/.knowledge-last-harvest"
: > "$marker"
epoch5="$(( $(date +%s) - 5 * 86400 ))"
touch -t "$(ts_for "$epoch5")" "$marker"
mkdir -p "$HOME/.claude/projects/proj1"
for i in 1 2 3; do
  dd if=/dev/zero of="$HOME/.claude/projects/proj1/t$i.jsonl" bs=1024 count=600 status=none
done
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ $CTX == *"Last /knowledge harvest: 5d ago"* ]] && ok "маркер 5 дней назад — '5d ago'" \
  || bad "'5d ago' в выводе" "$CTX"
[[ $CTX == *"3 substantial sessions"* ]] && ok "число сессий после маркера верное (3)" \
  || bad "число сессий после маркера" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== knowledge harvest: свежий маркер (1 день) — строка не показывается ==\n'
HOME="$(mktemp -d)"; export HOME
mkdir -p "$HOME/.claude"
marker="$HOME/.claude/.knowledge-last-harvest"
: > "$marker"
epoch1="$(( $(date +%s) - 1 * 86400 ))"
touch -t "$(ts_for "$epoch1")" "$marker"
mkdir -p "$HOME/.claude/projects/proj1"
for i in 1 2 3; do
  dd if=/dev/zero of="$HOME/.claude/projects/proj1/u$i.jsonl" bs=1024 count=600 status=none
done
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ $CTX != *"Last /knowledge harvest"* ]] && ok "маркер младше 2 дней — строка не показана" \
  || bad "строка не должна показываться при days<2" "$CTX"
rm -rf "$R" "$HOME"

printf '\n== knowledge harvest: маркер старый, но новых сессий меньше 3 — строка не показывается ==\n'
HOME="$(mktemp -d)"; export HOME
mkdir -p "$HOME/.claude"
marker="$HOME/.claude/.knowledge-last-harvest"
: > "$marker"
epoch5="$(( $(date +%s) - 5 * 86400 ))"
touch -t "$(ts_for "$epoch5")" "$marker"
mkdir -p "$HOME/.claude/projects/proj1"
dd if=/dev/zero of="$HOME/.claude/projects/proj1/only.jsonl" bs=1024 count=600 status=none
R="$(newrepo)"
run_hook "" "startup" "$R"
[[ $CTX != *"Last /knowledge harvest"* ]] && ok "меньше 3 сессий с маркера — строка не показана" \
  || bad "строка не должна показываться при since<3" "$CTX"
rm -rf "$R" "$HOME"

printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
