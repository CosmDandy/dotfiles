#!/usr/bin/env bash
# Tests for sessionend-leftovers.sh: branches and worktrees a session created and left
# behind become open TODO items; clean sessions write nothing.
#
# Usage: bash tools/claude/hooks/sessionend-leftovers.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sessionend-leftovers.sh"
command -v jq >/dev/null || { echo "jq required"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }
has() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3" "no '$2' in $1"; fi; }
hasnt() { if grep -qF -- "$2" "$1" 2>/dev/null; then bad "$3" "found '$2'"; else ok "$3"; fi; }

SID=aaaabbbb-1111-2222-3333-444455556666
SID8=aaaabbbb

newrepo() {
  local r; r="$(mktemp -d)"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.invalid
  git -C "$r" config user.name t
  git -C "$r" config core.hooksPath /dev/null  # the global gitleaks/commit-msg hooks are not under test
  git -C "$r" commit -q --allow-empty -m 'chore: root'
  printf '%s' "$r"
}

# transcript <cmd>... -> path of a jsonl with one Bash tool_use per command
transcript() {
  local f; f="$(mktemp --suffix=.jsonl 2>/dev/null || mktemp)"
  for c in "$@"; do
    if [[ "$c" == ENTERWORKTREE:* ]]; then
      jq -nc --arg n "${c#ENTERWORKTREE:}" \
        '{type:"assistant",message:{content:[{type:"tool_use",name:"EnterWorktree",input:{name:$n}}]}}'
    else
      jq -nc --arg c "$c" '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}'
    fi
  done > "$f"
  # a sidechain record must be ignored
  jq -nc '{type:"assistant",isSidechain:true,message:{content:[{type:"tool_use",name:"Bash",input:{command:"git switch -c ghost/branch"}}]}}' >> "$f"
  printf '%s' "$f"
}

run() { jq -nc --arg s "$SID" --arg c "$1" --arg t "$2" '{session_id:$s,cwd:$c,transcript_path:$t}' | "$HOOK"; }

printf '\n== leftovers are written ==\n'
R="$(newrepo)"
git -C "$R" switch -q -c feat/open && git -C "$R" commit -q --allow-empty -m 'feat: open' && git -C "$R" switch -q main
git -C "$R" switch -q -c feat/merged && git -C "$R" commit -q --allow-empty -m 'feat: merged' && git -C "$R" switch -q main && git -C "$R" merge -q feat/merged
git -C "$R" worktree add -q "$R/.claude/worktrees/wt1" -b worktree-wt1 2>/dev/null
T="$(transcript 'git switch -c feat/open && git commit -m x' 'git checkout -b feat/merged' 'git worktree add .claude/worktrees/wt1 -b worktree-wt1' 'git switch -c feat/deleted' 'git branch -d feat/deleted')"
run "$R" "$T"
todo="$R/TODO.$SID8.md"
[[ -f "$todo" ]] && ok "TODO fragment created" || bad "TODO fragment created"
has   "$todo" 'branch feat/open not merged into main'  'unmerged branch listed'
has   "$todo" 'branch feat/merged already in main'     'merged branch listed as deletable'
has   "$todo" 'worktree .claude/worktrees/wt1 still exists' 'leftover worktree listed'
hasnt "$todo" 'feat/deleted'                           'deleted branch not listed'
hasnt "$todo" 'ghost/branch'                           'sidechain command ignored'
has   "$todo" 'branch worktree-wt1 already in main'    'worktree branch with no commits is deletable'
run "$R" "$T"
[[ "$(grep -c 'feat/open' "$todo")" == 1 ]] && ok "second run does not duplicate items" || bad "second run does not duplicate items"
rm -f "$T"; git -C "$R" worktree remove --force "$R/.claude/worktrees/wt1" 2>/dev/null; rm -rf "$R"

printf '\n== EnterWorktree and the main-checkout redirect ==\n'
R="$(newrepo)"
git -C "$R" worktree add -q "$R/.claude/worktrees/fix+dns" -b 'worktree-fix+dns' 2>/dev/null
T="$(transcript 'ENTERWORKTREE:fix/dns')"
run "$R/.claude/worktrees/fix+dns" "$T"   # cwd is the worktree itself
has "$R/TODO.$SID8.md" 'worktree .claude/worktrees/fix+dns still exists' 'EnterWorktree name mapped (/ -> +), TODO lands in main checkout'
has "$R/TODO.$SID8.md" 'branch worktree-fix+dns already in main' 'EnterWorktree branch listed'
rm -f "$T"; git -C "$R" worktree remove --force "$R/.claude/worktrees/fix+dns" 2>/dev/null; rm -rf "$R"

printf '\n== clean session writes nothing ==\n'
R="$(newrepo)"
T="$(transcript 'git switch -c feat/tidy' 'git switch main' 'git branch -d feat/tidy' 'git status --short')"
run "$R" "$T"
[[ -f "$R/TODO.$SID8.md" ]] && bad "no TODO for a clean session" || ok "no TODO for a clean session"
T2="$(transcript 'ls' 'git status')"
run "$R" "$T2"
[[ -f "$R/TODO.$SID8.md" ]] && bad "no TODO when nothing was created" || ok "no TODO when nothing was created"
rm -f "$T" "$T2"; rm -rf "$R"

printf '\n== an existing TODO is appended, not replaced ==\n'
R="$(newrepo)"
git -C "$R" switch -q -c feat/open && git -C "$R" switch -q main
printf '# TODO\n- [ ] my own item\n' > "$R/TODO.$SID8.md"
T="$(transcript 'git switch -c feat/open')"
run "$R" "$T"
has "$R/TODO.$SID8.md" 'my own item'        'existing items kept'
has "$R/TODO.$SID8.md" 'branch feat/open'   'leftover appended'
rm -f "$T"; rm -rf "$R"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
