#!/usr/bin/env bash
# Tests for the commit-msg hook: conventional subject, no Cyrillic, visible skip.
#
# Usage: bash tools/git/hooks/commit-msg.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/commit-msg"
pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

# chk <want: pass|reject> <description> <message...>
chk() {
  local want=$1 desc=$2 f rc
  shift 2
  f="$(mktemp)"
  printf '%s\n' "$@" > "$f"
  "$HOOK" "$f" 2>/dev/null; rc=$?
  rm -f "$f"
  if [[ $want == pass && $rc -eq 0 ]] || [[ $want == reject && $rc -ne 0 ]]; then
    ok "$desc"
  else
    bad "$desc" "exit $rc, wanted $want"
  fi
}

printf '\n== subject ==\n'
chk pass   'plain feat'                      'feat: add the thing'
chk pass   'scope and breaking mark'         'fix(guard)!: close the gap'
chk pass   'wip is allowed'                  'wip(guard): Go-only push gates'
chk reject 'no type'                         'add the thing'
chk reject 'PR title shape'                  'NixOS (#16)'
chk reject 'type without colon-space'        'feat:add'
chk reject 'unknown type'                    'feature: add'
chk pass   'merge subject from git'          'Merge branch feat/x into main'
chk pass   'revert subject from git'         'Revert "feat: add the thing"' '' 'This reverts commit abc.'
chk pass   'fixup subject from git'          'fixup! feat: add the thing'

printf '\n== language ==\n'
chk reject 'Cyrillic subject'                'feat: добавить штуку'
chk reject 'Cyrillic in body'                'feat: add the thing' '' 'Потому что так надо.'
chk reject 'one Cyrillic word in Latin text' 'docs(rules): use_sops only in the root .envrc репозитория'
chk pass   'Cyrillic only in comment lines'  'feat: add the thing' '' '# Пожалуйста, введите сообщение коммита'
chk pass   'Cyrillic after the scissors'     'feat: add the thing' '# ------------------------ >8 ------------------------' 'diff --git a/x b/x' '+# комментарий в диффе'
chk pass   'ё and й in a comment only'       'chore: bump' '# ещё один комментарий'

printf '\n== skip ==\n'
f="$(mktemp)"; printf 'плохое сообщение\n' > "$f"
if COMMIT_MSG_SKIP=1 "$HOOK" "$f" 2>/dev/null; then ok 'COMMIT_MSG_SKIP=1 passes anything'; else bad 'COMMIT_MSG_SKIP=1 passes anything'; fi
rm -f "$f"
f="$(mktemp)"; printf '\n# only comments\n' > "$f"
if "$HOOK" "$f" 2>/dev/null; then ok 'empty message is left to git'; else bad 'empty message is left to git'; fi
rm -f "$f"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
