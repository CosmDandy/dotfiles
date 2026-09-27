#!/usr/bin/env bash
# Stop: keep an unattended run on its own checklist, with a hard cap on how many
# times this hook may nudge it.
#
# Usage: before starting an unattended run, write its open items to
# TODO.<sid8>.md (sid8 = first 8 chars of session_id — sessionstart-state.sh
# already tells the model this convention) as markdown checkboxes: `- [ ]` open,
# `- [x]` done. As long as that file exists and has open items, a Stop with no
# stated blocker gets sent back with a short reminder naming the first 5 open
# items, instead of ending the turn.
#
# Cap: at most STOP_CONTINUE_MAX (default 3) automatic continuations per session
# — a genuinely stuck run must end and get reviewed, not repeat forever. Do not
# run this alongside `/goal`: that is a second, unrelated Stop hook deciding
# whether to continue from a spoken condition instead of a checklist, and the
# two stacking is exactly how one audited session got 578 Stop-hook firings and
# 1.3B input tokens out of a goal with no checkable condition.
#
# NOTE: stop_hook_active=true is the NORMAL state on every continuation this
# hook itself grants — per the hooks reference (code.claude.com/docs/en/hooks.md,
# Stop input), it is "true when Claude Code is already continuing as a result of
# a stop hook". Exiting silently on it would cap this hook at exactly one
# continuation ever, which defeats the feature; it IS the intended re-entry
# path. What actually bounds the loop is the persistent per-session counter
# below, which does not depend on stop_hook_active at all.
#
# NOTE: never block from an uncertain read. If the transcript fallback for the
# last message can't be parsed at all, the hook stays silent rather than
# blocking on a guess — a wrong "let it stop" costs one review, a wrong "keep
# going" can spend the rest of the cap on nothing.
set -uo pipefail

input="$(cat)"
sid="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"
[[ -n "$sid" ]] || exit 0
sid8="${sid:0:8}"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)"
have_last_msg="$(jq -r 'has("last_assistant_message")' <<<"$input" 2>/dev/null)"
last_msg="$(jq -r '.last_assistant_message // empty' <<<"$input" 2>/dev/null)"

[[ -n "$cwd" ]] || exit 0
cd "$cwd" 2>/dev/null || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$root" ]] || exit 0

# NOTE: same worktree redirection as sessionend-fold.sh — the checklist lives in
# the MAIN checkout, not under --show-toplevel, whenever this session is running
# from a worktree. Told apart by git-dir differing from common-dir.
gitdir="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)"
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [[ -n "$common" && "$gitdir" != "$common" ]]; then
  main_root="$(dirname "$common")"
  [[ -d "$main_root" ]] && root="$main_root"
fi

todo="$root/TODO.${sid8}.md"
[[ -f "$todo" ]] || exit 0

open_items="$(grep -E '^[[:space:]]*- \[ \]' "$todo" 2>/dev/null)"
[[ -n "$open_items" ]] || exit 0

# The last message is the authoritative source per the hooks reference (it may be
# missing from the transcript at Stop time even when the field is populated), so
# it is read straight from the input. The transcript is only a fallback for
# harnesses that don't send the field yet.
msg_text="$last_msg"
if [[ "$have_last_msg" != "true" ]]; then
  msg_text=""
  if [[ -n "$transcript" && -f "$transcript" ]]; then
    msg_text="$(tail -n 200 "$transcript" 2>/dev/null | jq -rs '
      map(select(.type == "assistant")) | last
      | if . == null then "" else ((.message.content // [])[]? | select(.type == "text") | .text) end
    ' 2>/dev/null)"
    # jq failing on unparseable JSONL means we cannot tell whether the run already
    # reported a blocker — stay silent rather than block on that guess.
    [[ $? -eq 0 ]] || exit 0
  fi
fi

# Job-list conventions (see CLAUDE.md): a line starting with one of these, or a
# statement that the run itself is blocked, means it already reported its own stop
# condition — nudging it again would talk over that report.
# NOTE: "blocked" alone is not a blocker: "the guard blocked the command" and
# "non-blocking" are ordinary progress prose. Only the run saying it IS blocked
# counts — "blocked on/by …", a line starting with "blocked:", or the Russian
# "заблокирован(а/о)" / "блокирует" as a statement, not "разблокирован".
if grep -qiE '^[[:space:]]*(needs input|failed|result):' <<<"$msg_text" \
  || grep -qiE '^[[:space:]]*blocked:|(^|[^[:alnum:]-])blocked (on|by)[[:space:]]|(^|[^[:alnum:]])(заблокирован[аоы]?|блокирует)([^[:alnum:]]|$)' <<<"$msg_text"; then
  exit 0
fi

max="${STOP_CONTINUE_MAX:-3}"

state_dir="${HOME}/.claude/.state/stop-continue"
mkdir -p "$state_dir" 2>/dev/null || exit 0
# latches are per session_id; drop stale ones so the directory does not grow forever
find "$state_dir" -type f -mtime +7 -delete 2>/dev/null || true
state="$state_dir/$sid"

count=0
prev_hash=""
prev_size=""
if [[ -f "$state" ]]; then
  count="$(jq -r '.count // 0' "$state" 2>/dev/null)"
  prev_hash="$(jq -r '.items_hash // empty' "$state" 2>/dev/null)"
  prev_size="$(jq -r '.transcript_size // empty' "$state" 2>/dev/null)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
fi

# NOTE: GNU form first — BSD md5sum does not exist at all under that name, only
# `md5`, which prints the bare digest when reading stdin (no filename to prefix).
items_hash="$(printf '%s' "$open_items" | md5sum 2>/dev/null | awk '{print $1}')"
[[ -n "$items_hash" ]] || items_hash="$(printf '%s' "$open_items" | md5 2>/dev/null)"

cur_size=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  cur_size="$(stat -c %s "$transcript" 2>/dev/null || stat -f %z "$transcript" 2>/dev/null)"
fi

# Stuck: the exact same open items as the last continuation, and nothing new on
# the transcript since — another nudge would only repeat itself forever, so stop
# regardless of how much of the cap is left.
if [[ -n "$prev_hash" && "$items_hash" == "$prev_hash" \
  && -n "$prev_size" && -n "$cur_size" && "$cur_size" == "$prev_size" ]]; then
  exit 0
fi

n_open="$(printf '%s\n' "$open_items" | grep -c .)"

if (( count >= max )); then
  note="stop-continue: stopped after ${count} continuation(s); ${n_open} item(s) still open in TODO.${sid8}.md"
  printf '%s\n' "$note" >&2
  jq -nc --arg m "$note" '{systemMessage:$m}'
  exit 0
fi

new_count=$((count + 1))
jq -nc --arg h "$items_hash" --arg s "${cur_size:-0}" --argjson c "$new_count" \
  '{count:$c, items_hash:$h, transcript_size:($s|tonumber)}' >"$state" 2>/dev/null

first5="$(printf '%s\n' "$open_items" \
  | sed -E 's/^[[:space:]]*- \[ \][[:space:]]*//' \
  | head -5 | awk 'ORS="; "' | sed -E 's/; $//')"

reason="Your task list still has open items: ${first5}. Continue with them. If one is blocked, say what is blocking it. (automatic continuation ${new_count} of ${max})"

jq -nc --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
