#!/usr/bin/env bash
# PreCompact: снять объективный снимок ДО того, как разговор схлопнется в сводку.
#
# Хук не знает выводов сессии и не пытается их угадать — он фиксирует то, что
# дороже всего восстанавливать и что теряется тише всего: на какой ветке шла
# работа и какие пути оказались тронуты к моменту компакта. Правило в CLAUDE.md
# просит записать находки заранее; оно advisory и срабатывает не всегда — этот
# хук даёт хотя бы фактическую опору.
#
# PROGRESS.md и PROGRESS.*.md лежат в глобальном gitignore, поэтому создать файл
# здесь безопасно: в коммит он не попадёт.
set -uo pipefail

input="$(cat)"
trigger="$(printf '%s' "$input" | jq -r '.trigger // "unknown"')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"
sid8="${sid:0:8}"

[[ -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# Снимок кладётся в фрагмент СВОЕЙ сессии, а не в общий PROGRESS.md: иначе он,
# во-первых, разлучается с текстовыми заметками того же хода, а во-вторых, обновляет
# mtime общего файла — и stop-progress.sh считает свежей чужую активность, переставая
# напоминать сессии, которая весь день ничего не записала.
if [[ -n "$sid8" ]]; then
  f="$root/PROGRESS.${sid8}.md"
else
  f="$root/PROGRESS.md"
fi
branch="$(git branch --show-current 2>/dev/null)"
dirty="$(git status --porcelain 2>/dev/null | head -25)"
stamp="$(date '+%Y-%m-%d %H:%M')"

if [[ ! -f "$f" ]]; then
  printf '# PROGRESS\n\n## Done\n\n## In progress\n\n## Next\n\n## Notes\n' > "$f" || exit 0
fi

{
  printf '\n<!-- compact %s (trigger: %s) -->\n' "$stamp" "$trigger"
  if [[ -n "$dirty" ]]; then
    printf -- '- Компакт на ветке `%s`. Незакоммиченное на этот момент:\n' "${branch:-?}"
    printf '%s\n' "$dirty" | sed 's/^/  - /'
  else
    printf -- '- Компакт на ветке `%s`, рабочее дерево чистое.\n' "${branch:-?}"
  fi
} >> "$f"

exit 0
