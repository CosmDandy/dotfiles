#!/usr/bin/env bash
# Behaviour tests for the PostToolUse(Failure) bash-trap hint — `claude-cli bashhint`
# (tools/claude/cli), the Go port of what used to be posttooluse-bashhint.sh.
#
# Each case is the shape of a real tool result from a transcript: the hook must answer with
# a hint on exactly these and stay silent on everything else — a hint on every Bash call
# would be noise the model learns to skip.
#
# Usage: bash tools/claude/hooks/posttooluse-bashhint.test.sh
# Needs jq and, unless BASHHINT_HOOK is set, go (to build claude-cli on the fly).
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

# BASHHINT_HOOK, like the guard test's GUARD_HOOK, points this suite at a specific
# implementation — e.g. "/path/to/claude-cli bashhint". Word-split on purpose: a binary
# plus its subcommand is two words, not one path. Unset, it builds claude-cli fresh.
if [[ -n ${BASHHINT_HOOK:-} ]]; then
  # shellcheck disable=SC2206
  HOOK_CMD=($BASHHINT_HOOK)
else
  CLI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../cli" && pwd)"
  BIN="$(mktemp -d)/claude-cli"
  (cd "$CLI_DIR" && go build -o "$BIN" .) || { echo "сборка claude-cli не удалась"; exit 2; }
  HOOK_CMD=("$BIN" bashhint)
fi
[[ -x ${HOOK_CMD[0]} ]] || { echo "не найден исполняемый ${HOOK_CMD[0]}"; exit 2; }
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
    | "${HOOK_CMD[@]}" | jq -r '.hookSpecificOutput.additionalContext // empty'
}

echo "— отказ харнеса не доходит до PostToolUseFailure — подсказки нет —"
h=$(run "cat > f <<EOF
x
EOF" 'This session is isolated in the worktree /w/.claude/worktrees/x, but this command is too complex to verify that it stays inside the worktree')
[[ -z $h ]] && ok "отказ изоляции worktree — тишина (guard закрывает это раньше)" || bad "лишняя подсказка на отказ харнеса" "$h"

echo "— пуш без PR —"
PUSH_OUT='remote:
remote: Create a pull request for '"'"'feat/x'"'"' on GitHub by visiting:
remote:      https://github.com/o/r/pull/new/feat/x
remote:
To github.com:o/r.git
 * [new branch]      feat/x -> feat/x'
h=$(run "git push -u origin feat/x" "$PUSH_OUT")
[[ $h == *"gh pr create"* ]] && ok "push без PR — напоминание gh pr create" || bad "push без PR" "$h"
h=$(run "git -C /w/repo push -u origin feat/x" "$PUSH_OUT")
[[ $h == *"gh pr create"* ]] && ok "git -C … push тоже" || bad "git -C push" "$h"
h=$(run "git push" "To github.com:o/r.git
   1234567..89abcde  feat/x -> feat/x")
[[ -z $h ]] && ok "push в ветку с PR — тишина" || bad "лишняя подсказка на обычный push" "$h"
h=$(run "gh pr view 12" "$PUSH_OUT")
[[ -z $h ]] && ok "тот же текст не от push — тишина" || bad "подсказка не на push" "$h"
# Regression: grep never lets a match span two physical lines, so "git" alone
# on one line and "push" starting the next must NOT read as a push — a
# multiline-mode port of the regex (rather than testing line by line) matched
# this and fired the hint spuriously.
h=$(run "$(printf 'git\npush')" "$PUSH_OUT")
[[ -z $h ]] && ok "git и push на разных строках — не пуш, тишина" || bad "лишняя подсказка: git/push через перевод строки" "$h"

echo "— старые случаи не сломаны —"
h=$(run "ls *.log" "zsh: no matches found: *.log")
[[ $h == *"null_glob"* ]] && ok "глоб без совпадений" || bad "глоб без совпадений" "$h"
h=$(run "ls" "file1 file2")
[[ -z $h ]] && ok "обычный вывод — тишина" || bad "подсказка на обычный вывод" "$h"

echo "— hookEventName эхом от входного события —"
event_of() {
  jq -nc --arg c "$1" --arg r "$2" --arg ev "$3" \
    '{hook_event_name:$ev, session_id:"'"$SID"'", tool_input:{command:$c}, tool_response:$r}' \
    | "${HOOK_CMD[@]}" | jq -r '.hookSpecificOutput.hookEventName // empty'
}
e=$(event_of "ls *.log" "zsh: no matches found: *.log" "PostToolUseFailure")
[[ $e == "PostToolUseFailure" ]] && ok "PostToolUseFailure эхом" || bad "PostToolUseFailure не эхом" "$e"
e=$(event_of "ls *.log" "zsh: no matches found: *.log" "PostToolUse")
[[ $e == "PostToolUse" ]] && ok "PostToolUse эхом" || bad "PostToolUse не эхом" "$e"

rm -rf "$TMPDIR"
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
