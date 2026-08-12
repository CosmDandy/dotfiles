#!/usr/bin/env bash
# SessionStart: surface state that is easy to lose track of between sessions.
#
# Three things only, all earned by real incidents:
#   1. uncommitted work inside the tools/claude/custom submodule — it lives in a
#      separate repo, so `git status` in the superproject shows only ` m <path>`
#      and the actual changes are invisible until you look inside.
#   2. a PROGRESS.md handoff in the repo root, plus any PROGRESS/TODO fragments
#      other sessions left behind — the per-session convention only works if the
#      next session actually reads what the previous one wrote.
#   3. knowledge left unharvested — /knowledge only runs when someone remembers
#      to call it, and nobody does. Reported as one line about how long it has
#      been, NOT as a list of unharvested sessions: at ~8 substantial sessions a
#      day that list is permanently non-empty and stops being read.
# Silent when there is nothing to report.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
sid8="${sid:0:8}"
src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null)"

out=""

if [[ -n "$sid8" ]]; then
  out+="Session id: ${sid8}. Per-session files go under this id: running handoff notes to PROGRESS.${sid8}.md (not PROGRESS.md directly), the session's task list to TODO.${sid8}.md."$'\n'
fi

sub="${HOME}/.dotfiles/tools/claude/custom"
if [[ -d "$sub/.git" || -f "$sub/.git" ]]; then
  dirty="$(git -C "$sub" status --porcelain 2>/dev/null | head -20)"
  if [[ -n "$dirty" ]]; then
    n="$(printf '%s\n' "$dirty" | grep -c . )"
    out+="The tools/claude/custom submodule has ${n} uncommitted path(s) — it is a separate repo, so a superproject commit will NOT include them:"$'\n'
    out+="$(printf '%s\n' "$dirty" | sed 's/^/  /')"$'\n'
  fi
fi

# Ищем от КОРНЯ репозитория, а не от cwd: precompact-snapshot.sh и sessionend-fold.sh
# работают от корня, и если claude запущен из подкаталога, пути разъезжаются —
# фрагмент пишется в подкаталог, а свёртка ищет его в корне и не находит.
root="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$root" ]] || root="."

# Компакт заменяет разговор сводкой, и всё, чего нет на диске, потеряно.
# precompact-snapshot.sh пишет снимок в фрагмент СВОЕЙ сессии — но обратно его никто
# не читал: SessionStart висит на общем matcher и источник не различал, показывая
# только ## Next из общего PROGRESS.md. Снимок писался в пустоту ровно в тот момент,
# когда он единственно и нужен. Здесь он возвращается в контекст.
if [[ "$src" == "compact" && -n "$sid8" && -f "$root/PROGRESS.${sid8}.md" ]]; then
  frag="$(tail -n 120 "$root/PROGRESS.${sid8}.md" | tail -c 8000)"
  if [[ -n "$frag" ]]; then
    out+="Контекст только что схлопнулся. Ниже — хвост собственного фрагмента этой сессии (PROGRESS.${sid8}.md): то, что было записано ДО компакта. Читай его как продолжение работы, а не как справку."$'\n'
    out+="$frag"$'\n\n'
  fi
fi

if [[ -f "$root/PROGRESS.md" ]]; then
  next="$(awk '/^## Next/{f=1;next} /^## /{f=0} f' "$root/PROGRESS.md" | grep -v '^[[:space:]]*$' | head -8)"
  if [[ -n "$next" ]]; then
    out+="PROGRESS.md handoff — ## Next:"$'\n'
    out+="$(printf '%s\n' "$next" | sed 's/^/  /')"$'\n'
  fi
fi

frags="$(find "$root" -maxdepth 1 \( -name 'PROGRESS.*.md' -o -name 'TODO.*.md' \) \
  ! -name "PROGRESS.${sid8}.md" ! -name "TODO.${sid8}.md" 2>/dev/null | sort)"
if [[ -n "$frags" ]]; then
  out+="Other sessions' per-session files present — read them before touching the same work. A PROGRESS fragment folds into PROGRESS.md; a TODO fragment is that session's unfinished list. Delete either only once its session has clearly ended:"$'\n'
  out+="$(printf '%s\n' "$frags" | sed 's/^/  /')"$'\n'
fi

marker="${HOME}/.claude/.knowledge-last-harvest"
proj="${HOME}/.claude/projects"
if [[ -d "$proj" ]]; then
  # maxdepth 2: deeper paths are subagent transcripts, not sessions of mine.
  # 500k is the rough floor for "something actually happened in here".
  if [[ -f "$marker" ]]; then
    # GNU-синтаксис первым: `stat -f %m` под GNU печатает в stdout блок про
    # файловую систему, и мусор попадает в переменную.
    mtime="$(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo 0)"
    days=$(( ( $(date +%s) - mtime ) / 86400 ))
    since="$(find "$proj" -maxdepth 2 -name '*.jsonl' -size +500k -newer "$marker" 2>/dev/null | grep -c .)"
    ago="${days}d ago"
  else
    days=99
    since="$(find "$proj" -maxdepth 2 -name '*.jsonl' -size +500k -mtime -14 2>/dev/null | grep -c .)"
    ago="never"
  fi
  if [[ "$days" -ge 2 && "$since" -ge 3 ]]; then
    out+="Last /knowledge harvest: ${ago}; ${since} substantial sessions since then. If this session turns up something worth keeping, offer it — the owner writes the note, you only outline."$'\n'
  fi
fi

[[ -n "$out" ]] || exit 0

jq -nc --arg c "$out" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
exit 0
