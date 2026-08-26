#!/usr/bin/env bash
# PreCompact: take an objective snapshot BEFORE the conversation collapses into a summary.
#
# The hook does not know the session's conclusions and does not guess them — it records what
# is most expensive to reconstruct and quietest to lose: the branch the work was on and
# which paths were touched by then. The CLAUDE.md rule asking for findings to be written
# down is advisory and does not always fire; this gives at least a factual anchor.
#
# NOTE: PROGRESS.md and PROGRESS.*.md are in the global gitignore, so creating the file
# here cannot end up in a commit.
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

# NOTE: the snapshot goes into THIS session's fragment rather than the shared PROGRESS.md —
# otherwise it is separated from the notes of the same turn and parallel sessions overwrite
# each other.
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
