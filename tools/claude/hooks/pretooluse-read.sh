#!/usr/bin/env bash
# PreToolUse guard for the Read tool.
#
# A whole file read into the context is the same loss as `cat`, one tool over: the
# audit of six background jobs found the same files read four to seven times, a few
# thousand lines each, into a context that then sat at 600k tokens for hours. A
# known file is read with offset/limit around the part that matters; what needs
# finding is found with Grep. Images, PDFs and notebooks are read whole by nature,
# scratch and logs are the job's own output, and short files cost nothing.
# NOTE: no `set -e` — a missing file or a failed wc must not kill the hook.
set -uo pipefail

input="$(cat)"
{ IFS= read -r f; IFS= read -r limit; } < <(printf '%s' "$input" \
  | jq -r '(.tool_input.file_path // ""), (.tool_input.limit // "")' 2>/dev/null)
[[ -n $f && -z $limit && -f $f ]] || exit 0

ext=$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')
case $ext in
  png|jpg|jpeg|gif|webp|svg|pdf|ipynb) exit 0 ;;
esac
grep -qE '^(/private)?/tmp/|CLAUDE_JOB_DIR|\.claude/jobs/[^/]+/tmp(/|$)|/scratchpad(/|$)|\.(output|log)$' <<<"$f" && exit 0

MAX=${READ_GUARD_MAX_LINES:-300}
n=$(wc -l <"$f" 2>/dev/null | tr -d ' ')
[[ ${n:-0} -gt $MAX ]] || exit 0

jq -nc --arg r "$f has $n lines — Read it with offset/limit around what you need, or Grep for it; a whole-file read stays in the context for good" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
