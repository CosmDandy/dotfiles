#!/usr/bin/env bash
# SessionEnd: fold this session's files into the shared PROGRESS.md and delete them.
#
# A hook rather than a rule because the rule already existed and was not followed: five
# PROGRESS fragments from five sessions and two TODOs had piled up in the repo root. An
# end-of-session ritual gets done by neither the human nor the model — by then neither has
# the context or a reason. A hook does.
#
# NOTE: the scope is deliberately narrow — only this session's fragment is folded. There is
# no reliable way to tell that another session has ended, and folding a live fragment would
# pull work out from under a running session. SessionStart still surfaces the others.
#
# NOTE: no `set -e` — this is cleanup, and a partial failure must not kill the rest.
set -uo pipefail

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
sid8="${sid:0:8}"
[[ -n "$sid8" && -n "$cwd" ]] || exit 0

cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# NOTE: in a worktree the fragment lives in the MAIN checkout (the next session would never
# find it under .claude/worktrees/<name>/), while --show-toplevel points at the worktree —
# so the hook would look where nothing is and exit silently, leaving the files forever. A
# worktree is told apart by git-dir differing from common-dir; in a submodule they match.
gitdir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [[ -n "$common" && "$gitdir" != "$common" ]]; then
  main_root="$(dirname "$common")"
  [[ -d "$main_root" ]] && root="$main_root"
fi

frag="$root/PROGRESS.${sid8}.md"
todo="$root/TODO.${sid8}.md"
main="$root/PROGRESS.md"
[[ -f "$frag" || -f "$todo" ]] || exit 0

# NOTE: locking by directory, not flock — flock does not exist in BSD userland at all,
# while mkdir is atomic everywhere. Failing to take it means another session is folding
# right now, and our files keep until next time.
lock="$root/.progress-fold.lock"
# NOTE: the trap releasing the lock does not run on SIGKILL (hook timeout, crash, shutdown),
# and a leftover directory would disable folding in this repository FOREVER and silently,
# while CLAUDE.md tells the model not to fold by hand. Folding takes a fraction of a second,
# so five minutes means a dead owner.
if [[ -d "$lock" ]]; then
  # NOTE: GNU form first — BSD answers `-c` with empty stdout and exit 1, while GNU reads
  # `-f` as --file-system and its output would land in the variable.
  mtime="$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null)"
  [[ -n "$mtime" ]] && (( $(date +%s) - mtime > 300 )) && rmdir "$lock" 2>/dev/null
fi
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

stamp="$(date '+%Y-%m-%d %H:%M')"
[[ -f "$main" ]] || printf '# PROGRESS\n\n## Done\n\n## In progress\n\n## Next\n\n## Notes\n' > "$main"

# Unfinished items go to ## Next — they are what the next session picks up. Closed ones are
# history and stay in git.
if [[ -f "$todo" ]]; then
  open_items="$(grep -E '^[[:space:]]*- \[ \]' "$todo" 2>/dev/null)"
  if [[ -n "$open_items" ]]; then
    items_file="$(mktemp)"
    printf '%s\n' "$open_items" | sed "s|^[[:space:]]*- \[ \]|- (сессия ${sid8})|" > "$items_file"
    tmp="$(mktemp)"
    awk -v f="$items_file" '
      { print }
      # NOTE: the heading is matched by PREFIX, exactly as sessionstart-state.sh reads it.
      # With an exact `^## Next$` a heading like "## Next steps" did not match, the fold
      # appended a SECOND section at the end of the file, and SessionStart kept showing the
      # first — so the task went to disk and was lost.
      /^## Next/ && !ins { while ((getline l < f) > 0) print l; close(f); ins = 1 }
      END { if (!ins) { print ""; print "## Next"; while ((getline l < f) > 0) print l } }
    ' "$main" > "$tmp" && mv "$tmp" "$main"
    rm -f "$items_file" "$tmp"
  fi
  rm -f "$todo"
fi

# The fragment itself goes to the end under a dated heading.
# NOTE: its first title line is dropped, or PROGRESS.md gets a second `# PROGRESS`.
if [[ -f "$frag" ]]; then
  body="$(sed '1{/^#[[:space:]]/d;}' "$frag")"
  if [[ -n "${body//[[:space:]]/}" ]]; then
    {
      printf '\n## Сессия %s — %s\n\n' "$sid8" "$stamp"
      printf '%s\n' "$body"
    } >> "$main"
  fi
  rm -f "$frag"
fi

exit 0
