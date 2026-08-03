#!/usr/bin/env bash
# Stop: не дать закончить сессию, в которой наработано заметно, а PROGRESS.md не
# тронут. Правило «обнови PROGRESS.md перед концом хода» в CLAUDE.md advisory —
# здесь оно становится обязательным.
#
# Блокирует ОДИН раз за сессию: маркер снимается только вместе с /tmp. Смысл —
# напомнить, а не запереть выход; со второго Stop ход завершается свободно.
set -uo pipefail

input="$(cat)"

# stop_hook_active = ход уже был продлён этим хуком; второй раз не вмешиваемся.
[[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" == "true" ]] && exit 0

sid="$(printf '%s' "$input" | jq -r '.session_id // "nosid"')"
sid8="${sid:0:8}"
mark="${TMPDIR:-/tmp}/claude-progress-nag-${sid}"
[[ -f "$mark" ]] && exit 0

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[[ -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# Порог: одна-две правки — это не «работа, которую жалко потерять».
changed="$(git status --porcelain 2>/dev/null | grep -c .)"
[[ "${changed:-0}" -lt 3 ]] && exit 0

# PROGRESS.md (и PROGRESS.<sid8>.md) в gitignore, поэтому судим по mtime, а не по git.
# Фрагмент своей сессии считается наравне с общим файлом — при нескольких
# параллельных агентах правки идут в PROGRESS.<sid8>.md, не в PROGRESS.md.
frag="$root/PROGRESS.${sid8}.md"
newest=0
for f in "$root/PROGRESS.md" "$frag"; do
  [[ -f "$f" ]] || continue
  # GNU-синтаксис ПЕРВЫМ: BSD не знает -c и падает молча, а GNU знает -f как
  # --file-system и на `-f %m` печатает в stdout блок про файловую систему —
  # мусор попадает в переменную и роняет арифметику ниже.
  m="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
  (( m > newest )) && newest=$m
done
if (( newest > 0 )); then
  now="$(date +%s)"
  (( now - newest < 3600 )) && exit 0
fi

touch "$mark"
jq -nc --arg r "В репозитории ${changed} изменённых путей, а PROGRESS.md/PROGRESS.${sid8}.md не обновлялись больше часа. Допиши в PROGRESS.${sid8}.md (свой файл — не трогай чужие фрагменты и общий PROGRESS.md, если рядом могут работать другие агенты) решения, тупики и точные команды, которые сработали — после компакта это единственный источник. Потом заканчивай ход." \
  '{decision:"block",reason:$r}'
exit 0
