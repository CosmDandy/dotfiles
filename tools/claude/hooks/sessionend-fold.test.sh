#!/usr/bin/env bash
# Behaviour tests for sessionend-fold.sh.
#
# Every case works against a throwaway git repo (mktemp) — running against a real checkout
# would fold a live session's fragment.
#
# Usage: bash tools/claude/hooks/sessionend-fold.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sessionend-fold.sh"
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

# run_hook <sid> <cwd> -> runs with cwd as $PWD (the hook cd's into .cwd from the input, but
# also needs a real working directory of its own since it is invoked as a plain command).
run_hook() {
  local sid=$1 cwd=$2
  jq -nc --arg s "$sid" --arg c "$cwd" --arg r "other" \
    '{session_id:$s, cwd:$c, reason:$r, hook_event_name:"SessionEnd"}' \
    | (cd "$cwd" && "$HOOK")
}

SID=aaaabbbb-0000-0000-0000-000000000001
SID8=aaaabbbb

printf '\n== ничего сворачивать — PROGRESS.md не создаётся ==\n'
R="$(newrepo)"
run_hook "$SID" "$R"
[[ -f "$R/PROGRESS.md" ]] && bad "без фрагментов PROGRESS.md не должен появляться" \
  || ok "без фрагментов PROGRESS.md не создан"
rm -rf "$R"

printf '\n== фрагмент без общего PROGRESS.md — создаётся с шапкой ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\nнаходка\n' > "$R/PROGRESS.$SID8.md"
run_hook "$SID" "$R"
[[ -f "$R/PROGRESS.md" ]] && ok "PROGRESS.md создан из фрагмента" || bad "PROGRESS.md создан"
grep -q 'находка' "$R/PROGRESS.md" && ok "содержимое фрагмента перенесено" \
  || bad "содержимое фрагмента перенесено"
grep -q '^## Done$' "$R/PROGRESS.md" && ok "шапка со стандартными секциями создана" \
  || bad "шапка со стандартными секциями"
[[ ! -f "$R/PROGRESS.$SID8.md" ]] && ok "фрагмент удалён после свёртки" \
  || bad "фрагмент удалён после свёртки"
rm -rf "$R"

printf '\n== TODO без фрагмента: открытые пункты уходят в ## Next, закрытые — нет ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n- старое\n' > "$R/PROGRESS.md"
printf -- '- [x] закрытое дело\n- [ ] открытое дело\n' > "$R/TODO.$SID8.md"
run_hook "$SID" "$R"
[[ ! -f "$R/TODO.$SID8.md" ]] && ok "TODO удалён" || bad "TODO удалён"
grep -q 'открытое дело' "$R/PROGRESS.md" && ok "открытый пункт перенесён" \
  || bad "открытый пункт перенесён"
grep -q 'закрытое дело' "$R/PROGRESS.md" && bad "закрытый пункт не должен переноситься" \
  || ok "закрытый пункт не перенесён"
grep -q "сессия $SID8" "$R/PROGRESS.md" && ok "перенесённый пункт помечен id сессии" \
  || bad "пункт помечен id сессии"
rm -rf "$R"

printf '\n== TODO без единого открытого пункта — секция ## Next не трогается ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n- прежнее\n' > "$R/PROGRESS.md"
printf -- '- [x] всё закрыто\n' > "$R/TODO.$SID8.md"
run_hook "$SID" "$R"
[[ ! -f "$R/TODO.$SID8.md" ]] && ok "TODO без открытых пунктов всё же удалён" \
  || bad "TODO удалён даже без открытых пунктов"
n="$(grep -c '^## Next' "$R/PROGRESS.md")"
[[ $n -eq 1 ]] && ok "секция ## Next не задвоилась" || bad "секция ## Next не задвоилась"
grep -q 'прежнее' "$R/PROGRESS.md" && ok "прежнее содержимое ## Next сохранено" \
  || bad "прежнее содержимое сохранено"
rm -rf "$R"

printf '\n== чужие фрагменты (другой sid) не трогаются ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf 'чужой фрагмент\n' > "$R/PROGRESS.ffffffff.md"
printf -- '- [ ] чужой todo\n' > "$R/TODO.ffffffff.md"
printf '# PROGRESS\n\nсвоё\n' > "$R/PROGRESS.$SID8.md"
run_hook "$SID" "$R"
[[ -f "$R/PROGRESS.ffffffff.md" ]] && ok "чужой PROGRESS-фрагмент не тронут" \
  || bad "чужой PROGRESS-фрагмент не тронут"
[[ -f "$R/TODO.ffffffff.md" ]] && ok "чужой TODO не тронут" || bad "чужой TODO не тронут"
grep -q 'чужой' "$R/PROGRESS.md" && bad "чужое содержимое не должно попасть в PROGRESS.md" \
  || ok "чужое содержимое не попало в PROGRESS.md"
grep -q 'своё' "$R/PROGRESS.md" && ok "собственный фрагмент свёрнут" \
  || bad "собственный фрагмент свёрнут"
rm -rf "$R"

printf '\n== worktree: фрагмент лежит в основном checkout, cwd — в воркетри ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\n## Next\n' > "$R/PROGRESS.md"
printf '# PROGRESS\n\nиз воркетри\n' > "$R/PROGRESS.$SID8.md"
printf -- '- [ ] задача из воркетри\n' > "$R/TODO.$SID8.md"
git -C "$R" worktree add -q -b wt-fold "$R/.claude/worktrees/wt-fold" 2>/dev/null
if [[ -d "$R/.claude/worktrees/wt-fold" ]]; then
  run_hook "$SID" "$R/.claude/worktrees/wt-fold"
  [[ ! -f "$R/PROGRESS.$SID8.md" ]] && ok "фрагмент в основном checkout свёрнут" \
    || bad "фрагмент в основном checkout свёрнут"
  [[ ! -f "$R/TODO.$SID8.md" ]] && ok "TODO в основном checkout удалён" \
    || bad "TODO в основном checkout удалён"
  grep -q 'из воркетри' "$R/PROGRESS.md" && ok "содержимое попало в основной PROGRESS.md" \
    || bad "содержимое попало в основной PROGRESS.md"
  grep -q 'задача из воркетри' "$R/PROGRESS.md" && ok "TODO-пункт попал в основной PROGRESS.md" \
    || bad "TODO-пункт попал в основной PROGRESS.md"
else
  printf '  SKIP  git worktree недоступен\n'
fi
rm -rf "$R"

printf '\n== пустой session_id или cwd — тишина ==\n'
R="$(newrepo)"
printf '# PROGRESS\n\nданные\n' > "$R/PROGRESS.$SID8.md"
jq -nc --arg c "$R" '{cwd:$c}' | (cd "$R" && "$HOOK")
[[ -f "$R/PROGRESS.$SID8.md" ]] && ok "без session_id фрагмент не тронут" \
  || bad "без session_id фрагмент не тронут"
rm -rf "$R"

printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
