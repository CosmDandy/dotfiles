#!/usr/bin/env bash
# SessionEnd: list what this session created in git and did not clean up — worktrees and
# branches — as open items in TODO.<sid8>.md, which sessionend-fold.sh then carries into
# PROGRESS.md ## Next for the next session to see.
#
# A hook rather than a rule because the rule exists (CLAUDE.md: "delete that branch and its
# worktree") and the transcripts say it is not followed: of 22 sessions that created a
# branch or worktree, 2 cleaned up fully, 9 partially, 9 not at all; four sessions shared
# one worktree branch and two force-deleted other sessions' branches. Nothing is removed
# here — another live session may be using the branch — the leftover is only written down.
#
# Must run BEFORE sessionend-fold.sh in settings.json (hooks run in list order).
# NOTE: no `set -e` — a grep with no match is the normal path here.
set -uo pipefail

input="$(cat)"
sid="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)"
sid8="${sid:0:8}"
[[ -n "$sid8" && -n "$cwd" && -f "$transcript" ]] || exit 0

cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
# NOTE: same worktree redirection as sessionend-fold.sh — the TODO lives in the MAIN
# checkout, and `git worktree list` / `git branch` are answered from there.
gitdir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [[ -n "$common" && "$gitdir" != "$common" ]]; then
  main_root="$(dirname "$common")"
  [[ -d "$main_root" ]] && root="$main_root"
fi
cd "$root" 2>/dev/null || exit 0

# Every Bash command this session ran, one per line (newlines inside a command folded).
cmds="$(jq -r 'select(.type=="assistant" and (.isSidechain|not))
  | .message.content[]? | select(.type=="tool_use")
  | if .name=="Bash" then (.input.command // "" | gsub("\n"; " "))
    elif .name=="EnterWorktree" then "ENTERWORKTREE " + (.input.name // "")
    else empty end' "$transcript" 2>/dev/null)"
[[ -n "$cmds" ]] || exit 0

branches=()
worktrees=()
while IFS= read -r line; do
  # git switch -c NAME / git checkout -b NAME
  if [[ "$line" =~ git[[:space:]]+(switch[[:space:]]+-c|checkout[[:space:]]+-b)[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
    branches+=("${BASH_REMATCH[2]}")
  fi
  # git worktree add [-b NAME] PATH [BRANCH]
  if [[ "$line" =~ git[[:space:]]+worktree[[:space:]]+add[[:space:]]+(.*) ]]; then
    rest="${BASH_REMATCH[1]%%[;&|]*}"
    if [[ "$rest" =~ -b[[:space:]]+([^[:space:]]+) ]]; then
      branches+=("${BASH_REMATCH[1]}")
      rest="${rest//-b ${BASH_REMATCH[1]}/}"
    fi
    for tok in $rest; do
      [[ "$tok" == -* ]] && continue
      worktrees+=("$tok")
      break
    done
  fi
  # EnterWorktree NAME -> .claude/worktrees/NAME on branch worktree-NAME ("/" becomes "+")
  if [[ "$line" =~ ^ENTERWORKTREE[[:space:]]+([^[:space:]]+) ]]; then
    name="${BASH_REMATCH[1]//\//+}"
    worktrees+=(".claude/worktrees/$name")
    branches+=("worktree-$name")
  fi
done <<<"$cmds"
(( ${#branches[@]} + ${#worktrees[@]} )) || exit 0

default="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[[ -n "$default" ]] || default="$(git branch --list main master | head -1 | tr -d ' *')"
current="$(git branch --show-current 2>/dev/null)"

items=()
seen=" "
for wt in "${worktrees[@]}"; do
  abs="$wt"; [[ "$abs" == /* ]] || abs="$root/$wt"
  abs="${abs%/}"
  [[ "$seen" == *" $abs "* ]] && continue; seen+="$abs "
  if git worktree list --porcelain 2>/dev/null | grep -qx "worktree $abs"; then
    items+=("worktree $wt still exists — remove it, or exit and let the next session decide")
  fi
done
for b in "${branches[@]}"; do
  [[ "$seen" == *" $b "* ]] && continue; seen+="$b "
  [[ -n "$(git branch --list "$b" 2>/dev/null)" ]] || continue
  [[ "$b" == "$default" ]] && continue
  if [[ -n "$default" ]] && git merge-base --is-ancestor "$b" "$default" 2>/dev/null; then
    state="already in $default — delete it"
  else
    state="not merged into ${default:-the default branch}"
    [[ "$b" == "$current" ]] && state+=" (session ended on it)"
  fi
  items+=("branch $b $state")
done
(( ${#items[@]} )) || exit 0

todo="$root/TODO.${sid8}.md"
[[ -f "$todo" ]] || printf '# TODO (session %s)\n\n' "$sid8" > "$todo"
for it in "${items[@]}"; do
  grep -qF -- "$it" "$todo" 2>/dev/null || printf -- '- [ ] leftover: %s\n' "$it" >> "$todo"
done
exit 0
