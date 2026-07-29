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

# PROGRESS.md в gitignore, поэтому судим по mtime, а не по git.
if [[ -f "$root/PROGRESS.md" ]]; then
  now="$(date +%s)"
  m="$(stat -f %m "$root/PROGRESS.md" 2>/dev/null || stat -c %Y "$root/PROGRESS.md" 2>/dev/null || echo 0)"
  (( now - m < 3600 )) && exit 0
fi

touch "$mark"
jq -nc --arg r "В репозитории ${changed} изменённых путей, а PROGRESS.md не обновлялся больше часа. Допиши туда решения, тупики и точные команды, которые сработали — после компакта это единственный источник. Потом заканчивай ход." \
  '{decision:"block",reason:$r}'
exit 0
