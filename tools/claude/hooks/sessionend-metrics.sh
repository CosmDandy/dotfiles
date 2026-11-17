#!/usr/bin/env bash
# SessionEnd: append this session's row from metrics/session-metrics.py to
# ~/.claude/metrics/sessions.jsonl, so the CLAUDE.md-compliance numbers accumulate on
# every machine without anyone remembering to run the script.
#
# One row per session: a resumed session ends several times, so its earlier row is
# dropped before the new one is appended (the last run sees the whole transcript).
# Weekly summaries are a jq over that file; the A/B check in
# tools/claude/custom/research/research-autonomy-audit-2026-10.md reads it.
# NOTE: no `set -e` — a missing python3 or transcript must not kill the SessionEnd chain.
set -uo pipefail

input="$(cat)"
sid="$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null)"
transcript="$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null)"
[[ -n "$sid" && -f "$transcript" ]] || exit 0

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../metrics/session-metrics.py"
[[ -f "$script" ]] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

out="${CLAUDE_METRICS_FILE:-$HOME/.claude/metrics/sessions.jsonl}"
mkdir -p "$(dirname "$out")" 2>/dev/null || exit 0

tmp="$(mktemp)"
if ! python3 -I "$script" --jsonl "$tmp" "$transcript" >/dev/null 2>&1; then
  rm -f "$tmp"; exit 0
fi
sid8="${sid:0:8}"
if [[ -f "$out" ]]; then
  prev="$(mktemp)"
  jq -c "select(.sid != \"$sid8\")" "$out" > "$prev" 2>/dev/null && mv "$prev" "$out"
  rm -f "$prev"
fi
cat "$tmp" >> "$out"
rm -f "$tmp"
exit 0
