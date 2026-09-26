#!/usr/bin/env bash
# Behaviour tests for posttooluse-bashhint.sh.
#
# Each case is the shape of a real tool result from a transcript: the hook must answer with
# a hint on exactly these and stay silent on everything else — a hint on every Bash call
# would be noise the model learns to skip.
#
# Usage: bash tools/claude/hooks/posttooluse-bashhint.test.sh
# Needs jq (so does the hook).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/posttooluse-bashhint.sh"
[[ -x $HOOK ]] || { echo "не найден исполняемый $HOOK"; exit 2; }
command -v jq >/dev/null || { echo "нужен jq"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

# The counter lives in TMPDIR keyed by session id; a private TMPDIR keeps runs independent.
TMPDIR="$(mktemp -d)"; export TMPDIR
SID=aaaabbbb-1111-2222-3333-444455556666

# run <command> <tool_response text> [session_id] -> additionalContext or empty
run() {
  jq -nc --arg c "$1" --arg r "$2" --arg s "${3:-$SID}" \
    '{hook_event_name:"PostToolUseFailure", session_id:$s, tool_input:{command:$c}, tool_response:$r}' \
    | "$HOOK" | jq -r '.hookSpecificOutput.additionalContext // empty'
}

WT_REJECT='This session is isolated in the worktree /w/.claude/worktrees/x, but this command is too complex to verify that it stays inside the worktree'

echo "— отказ изоляции worktree —"
h=$(run "python3 - <<'PY'
print(1)
PY" "$WT_REJECT")
[[ $h == *"Edit"* && $h == *"CLAUDE_JOB_DIR"* ]] && ok "первый отказ: подсказка Edit/Write" || bad "первый отказ" "$h"
[[ $h != *"-й отказ"* ]] && ok "первый отказ не считается повтором" || bad "первый отказ помечен повтором" "$h"
h=$(run "cat > f <<EOF
x
EOF" "$WT_REJECT")
[[ $h == *"2-й отказ"* ]] && ok "второй отказ в той же сессии — счётчик" || bad "второй отказ" "$h"
h=$(run "cat > f <<EOF
x
EOF" "$WT_REJECT" bbbbcccc-0000-0000-0000-000000000000)
[[ $h != *"-й отказ"* ]] && ok "другая сессия — счёт с нуля" || bad "счётчик протёк между сессиями" "$h"

echo "— пуш без PR —"
PUSH_OUT='remote:
remote: Create a pull request for '"'"'feat/x'"'"' on GitHub by visiting:
remote:      https://github.com/o/r/pull/new/feat/x
remote:
To github.com:o/r.git
 * [new branch]      feat/x -> feat/x'
h=$(run "git push -u origin feat/x" "$PUSH_OUT")
[[ $h == *"gh pr create"* ]] && ok "push без PR — напоминание gh pr create" || bad "push без PR" "$h"
h=$(run "git push" "To github.com:o/r.git
   1234567..89abcde  feat/x -> feat/x")
[[ -z $h ]] && ok "push в ветку с PR — тишина" || bad "лишняя подсказка на обычный push" "$h"
h=$(run "gh pr view 12" "$PUSH_OUT")
[[ -z $h ]] && ok "тот же текст не от push — тишина" || bad "подсказка не на push" "$h"

echo "— старые случаи не сломаны —"
h=$(run "ls *.log" "zsh: no matches found: *.log")
[[ $h == *"null_glob"* ]] && ok "глоб без совпадений" || bad "глоб без совпадений" "$h"
h=$(run "ls" "file1 file2")
[[ -z $h ]] && ok "обычный вывод — тишина" || bad "подсказка на обычный вывод" "$h"

rm -rf "$TMPDIR"
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
