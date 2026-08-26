#!/usr/bin/env bash
# Tests for the session lifecycle hooks: SessionStart(compact) and SessionEnd(fold).
#
# Both work with files in the repository root, so every case runs in a throwaway git repo
# created with mktemp — running against the real .dotfiles would fold a live session's
# fragment.
#
# Usage: bash tools/claude/hooks/session-lifecycle.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOKS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
START="$HOOKS/sessionstart-state.sh"
FOLD="$HOOKS/sessionend-fold.sh"
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }
check(){ if [[ $1 == "$2" ]]; then ok "$3"; else bad "$3" "ждали [$2], получили [$1]"; fi; }

newrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  printf '%s' "$r"
}

SID=aaaabbbb-1111-2222-3333-444455556666
SID8=aaaabbbb

printf '\n== SessionStart: хвост фрагмента возвращается только после компакта ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n- пункт из общего файла\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nнаходка, записанная до компакта\n' > "$R/PROGRESS.$SID8.md"
run_start() {
  jq -nc --arg s "$SID" --arg src "$1" --arg c "$R" \
    '{session_id:$s,source:$src,cwd:$c}' \
    | (cd "$R" && "$START") | jq -r '.hookSpecificOutput.additionalContext // ""'
}
out="$(run_start compact)"
grep -q 'находка, записанная до компакта' <<<"$out" && ok "compact: хвост фрагмента отдан" \
  || bad "compact: хвост фрагмента отдан" "в выводе его нет"
grep -q 'схлопнулся' <<<"$out" && ok "compact: есть пояснение, что это продолжение работы" \
  || bad "compact: есть пояснение"
out="$(run_start startup)"
grep -q 'находка, записанная до компакта' <<<"$out" && bad "startup: хвоста быть не должно" \
  || ok "startup: хвоста нет"
grep -q 'пункт из общего файла' <<<"$out" && ok "startup: ## Next из общего PROGRESS.md на месте" \
  || bad "startup: ## Next на месте"
rm -rf "$R"

printf '\n== SessionEnd: свёртка фрагмента и TODO ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Done\n\n## Next\n- старый пункт\n\n## Notes\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nчто выяснили в сессии\n' > "$R/PROGRESS.$SID8.md"
printf '## 2026-08-08\n- [x] 10:00→10:30 сделанное\n- [ ] незакрытое дело\n' > "$R/TODO.$SID8.md"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")

[[ -f "$R/PROGRESS.$SID8.md" ]] && bad "фрагмент удалён" || ok "фрагмент удалён"
[[ -f "$R/TODO.$SID8.md" ]]     && bad "TODO удалён"     || ok "TODO удалён"
grep -q 'что выяснили в сессии' "$R/PROGRESS.md" && ok "содержимое фрагмента в PROGRESS.md" \
  || bad "содержимое фрагмента в PROGRESS.md"
grep -q "## Сессия $SID8" "$R/PROGRESS.md" && ok "фрагмент под датированным заголовком" \
  || bad "фрагмент под датированным заголовком"
grep -q 'незакрытое дело' "$R/PROGRESS.md" && ok "незакрытая задача перенесена" \
  || bad "незакрытая задача перенесена"
grep -q 'сделанное' "$R/PROGRESS.md" && bad "закрытую задачу переносить не надо" \
  || ok "закрытая задача не перенесена"
# Unfinished items must land in ## Next, not at the end of the file — SessionStart reads
# only that section, and an item outside it is invisible to the next session.
nextblk="$(awk '/^## Next/{f=1;next} /^## /{f=0} f' "$R/PROGRESS.md")"
grep -q 'незакрытое дело' <<<"$nextblk" && ok "незакрытая задача именно в секции ## Next" \
  || bad "незакрытая задача в секции ## Next" "попала мимо секции"
grep -q 'старый пункт' <<<"$nextblk" && ok "прежнее содержимое ## Next не затёрто" \
  || bad "прежнее содержимое ## Next не затёрто"
c="$(grep -c '^# PROGRESS' "$R/PROGRESS.md")"
check "$c" "1" "второй заголовок # PROGRESS не появился"
rm -rf "$R"

printf '\n== SessionEnd: краевые случаи ==\n'
R="$(newrepo)"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ -f "$R/PROGRESS.md" ]] && bad "без файлов сессии PROGRESS.md не создаётся" \
  || ok "без файлов сессии ничего не создаётся"
rm -rf "$R"

# Other sessions' fragments must be left alone: there is no reliable way to tell that a
# session has ended, and folding a live one pulls work out from under it.
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf 'чужое\n' > "$R/PROGRESS.ffffffff.md"
printf '# PROGRESS\n\nсвоё\n' > "$R/PROGRESS.$SID8.md"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ -f "$R/PROGRESS.ffffffff.md" ]] && ok "чужой фрагмент не тронут" || bad "чужой фрагмент не тронут"
grep -q 'чужое' "$R/PROGRESS.md" && bad "чужое не должно попасть в PROGRESS.md" \
  || ok "чужое в PROGRESS.md не попало"
rm -rf "$R"

# While the .progress-fold.lock directory exists, no folding happens.
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nсвоё\n' > "$R/PROGRESS.$SID8.md"
mkdir "$R/.progress-fold.lock"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ -f "$R/PROGRESS.$SID8.md" ]] && ok "под чужой блокировкой свёртка не идёт" \
  || bad "под чужой блокировкой свёртка не идёт"
rmdir "$R/.progress-fold.lock"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ -f "$R/PROGRESS.$SID8.md" ]] && bad "после снятия блокировки свёртка проходит" \
  || ok "после снятия блокировки свёртка проходит"
[[ -d "$R/.progress-fold.lock" ]] && bad "блокировка снята после работы" \
  || ok "блокировка снята после работы"
rm -rf "$R"

# A stale lock: the EXIT trap does not run on SIGKILL, and a leftover directory would
# disable folding in the repository forever and silently — while CLAUDE.md forbids the
# model from folding by hand.
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nсвоё\n' > "$R/PROGRESS.$SID8.md"
mkdir "$R/.progress-fold.lock"
touch -t 200001010000 "$R/.progress-fold.lock"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ -f "$R/PROGRESS.$SID8.md" ]] && bad "протухшая блокировка не блокирует" \
  || ok "протухшая блокировка снята, свёртка прошла"
rm -rf "$R"

# A "## Next" heading with a tail. The fold matched exactly while SessionStart matches by
# prefix, so the task went into a SECOND section at the end of the file and was never
# shown to the next session.
R="$(newrepo)"
printf '# PROGRESS\n\n## Next steps\n- прежнее\n' > "$R/PROGRESS.md"
printf -- '- [ ] 10:00 незакрытая\n' > "$R/TODO.$SID8.md"
jq -nc --arg s "$SID" --arg c "$R" '{session_id:$s,cwd:$c}' | (cd "$R" && "$FOLD")
[[ "$(grep -c '^## Next' "$R/PROGRESS.md")" -eq 1 ]] \
  && ok "второй заголовок ## Next не появился" || bad "второй заголовок ## Next не появился"
awk '/^## Next/{n=1} n && /незакрытая/{found=1} END{exit !found}' "$R/PROGRESS.md" \
  && ok "задача попала в существующую секцию ## Next" \
  || bad "задача попала в существующую секцию ## Next"
rm -rf "$R"

# In a worktree the fragment is written to the MAIN checkout while the session's cwd is
# the worktree itself. The hook has to fold it where it actually lies, or fragments pile up
# in exactly the scenario the hook exists for.
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nиз worktree\n' > "$R/PROGRESS.$SID8.md"
printf -- '- [ ] 11:00 из worktree\n' > "$R/TODO.$SID8.md"
git -C "$R" worktree add -q -b wt "$R/.claude/worktrees/wt" 2>/dev/null
if [[ -d "$R/.claude/worktrees/wt" ]]; then
  jq -nc --arg s "$SID" --arg c "$R/.claude/worktrees/wt" '{session_id:$s,cwd:$c}' \
    | (cd "$R/.claude/worktrees/wt" && "$FOLD")
  [[ -f "$R/PROGRESS.$SID8.md" ]] && bad "из worktree фрагмент свёрнут" \
    || ok "из worktree фрагмент свёрнут"
  grep -q 'из worktree' "$R/PROGRESS.md" && ok "содержимое попало в основной PROGRESS.md" \
    || bad "содержимое попало в основной PROGRESS.md"
  [[ -f "$R/TODO.$SID8.md" ]] && bad "из worktree TODO свёрнут" || ok "из worktree TODO свёрнут"
else
  printf '  SKIP  git worktree недоступен\n'
fi
rm -rf "$R"

printf '\nпройдено: %d, провалено: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
