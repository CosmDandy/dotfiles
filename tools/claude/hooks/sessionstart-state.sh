#!/usr/bin/env bash
# SessionStart: surface state that is easy to lose track of between sessions.
#
# Two things only, both earned by real incidents:
#   1. uncommitted work inside the tools/claude/custom submodule — it lives in a
#      separate repo, so `git status` in the superproject shows only ` m <path>`
#      and the actual changes are invisible until you look inside.
#   2. a PROGRESS.md handoff in the working directory — the long-run convention
#      only works if the next session actually reads it.
# Silent when there is nothing to report.
set -uo pipefail

out=""

sub="${HOME}/.dotfiles/tools/claude/custom"
if [[ -d "$sub/.git" || -f "$sub/.git" ]]; then
  dirty="$(git -C "$sub" status --porcelain 2>/dev/null | head -20)"
  if [[ -n "$dirty" ]]; then
    n="$(printf '%s\n' "$dirty" | grep -c . )"
    out+="The tools/claude/custom submodule has ${n} uncommitted path(s) — it is a separate repo, so a superproject commit will NOT include them:"$'\n'
    out+="$(printf '%s\n' "$dirty" | sed 's/^/  /')"$'\n'
  fi
fi

if [[ -f PROGRESS.md ]]; then
  next="$(awk '/^## Next/{f=1;next} /^## /{f=0} f' PROGRESS.md | grep -v '^[[:space:]]*$' | head -8)"
  if [[ -n "$next" ]]; then
    out+="PROGRESS.md handoff — ## Next:"$'\n'
    out+="$(printf '%s\n' "$next" | sed 's/^/  /')"$'\n'
  fi
fi

[[ -n "$out" ]] || exit 0

jq -nc --arg c "$out" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
