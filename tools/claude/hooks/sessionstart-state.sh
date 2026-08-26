#!/usr/bin/env bash
# SessionStart: surface state that is easy to lose track of between sessions.
#
# Three things only, each earned by a real incident:
#   1. uncommitted work inside the tools/claude/custom submodule — it is a separate repo,
#      so `git status` in the superproject shows only ` m <path>`;
#   2. the PROGRESS.md handoff plus any fragments other sessions left behind — the
#      per-session convention only works if the next session reads them;
#   3. knowledge left unharvested — reported as ONE line about how long it has been, not as
#      a list of sessions: at ~8 substantial sessions a day such a list is permanently
#      non-empty and stops being read.
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

# NOTE: searched from the repository ROOT, not from cwd — precompact-snapshot.sh and
# sessionend-fold.sh work from the root, so with claude started in a subdirectory the
# fragment would be written there while the fold looks for it in the root.
root="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -n "$root" ]] || root="."

# A compact replaces the conversation with a summary, and anything not on disk is lost.
# NOTE: precompact-snapshot.sh writes its snapshot into this session's fragment, but
# nothing read it back — SessionStart hangs on a shared matcher and did not distinguish the
# source, showing only ## Next from the common PROGRESS.md. The snapshot was written into
# the void at exactly the moment it was needed.
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
    # NOTE: GNU form first — under GNU `stat -f %m` prints a filesystem block into stdout
    # and the junk ends up in the variable.
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
