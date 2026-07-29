#!/usr/bin/env bash
# PreCompact: снять объективный снимок ДО того, как разговор схлопнется в сводку.
#
# Хук не знает выводов сессии и не пытается их угадать — он фиксирует то, что
# дороже всего восстанавливать и что теряется тише всего: на какой ветке шла
# работа и какие пути оказались тронуты к моменту компакта. Правило в CLAUDE.md
# просит записать находки заранее; оно advisory и срабатывает не всегда — этот
# хук даёт хотя бы фактическую опору.
#
# PROGRESS.md лежит в глобальном gitignore, поэтому создать его здесь безопасно:
# в коммит он не попадёт.
set -uo pipefail

input="$(cat)"
trigger="$(printf '%s' "$input" | jq -r '.trigger // "unknown"')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

[[ -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

f="$root/PROGRESS.md"
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
