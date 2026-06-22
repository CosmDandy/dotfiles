#!/usr/bin/env bash
# PostToolUse hook: lint a file right after Claude edits/writes it.
# Non-blocking — surfaces linter output back to Claude via additionalContext.
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[[ -n "$file" && -f "$file" ]] || exit 0

out=""
run() { # $1 = linter binary, rest = command
  command -v "$1" >/dev/null 2>&1 || return 0
  local res
  res="$("${@:2}" 2>&1)" || true
  [[ -n "$res" ]] && out+="\$ ${*:2}"$'\n'"$res"$'\n\n'
}

case "$file" in
  *.tf|*.tfvars)
    run terraform terraform fmt -check -diff "$(dirname "$file")"
    ;;
  *.py)
    run ruff ruff check "$file"
    ;;
  *.sh|*.bash)
    run shellcheck shellcheck -S warning "$file"
    ;;
  *.yml|*.yaml)
    run yamllint yamllint -d relaxed "$file"
    if grep -qE '^apiVersion:' "$file" && grep -qE '^kind:' "$file"; then
      run kubeconform kubeconform -strict -summary "$file"
    fi
    case "$file" in
      */tasks/*|*/playbooks/*|*/roles/*|*playbook*)
        run ansible-lint ansible-lint "$file"
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

[[ -z "$out" ]] && exit 0

jq -nc --arg ctx "Lint results for $file:"$'\n'"$out" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
