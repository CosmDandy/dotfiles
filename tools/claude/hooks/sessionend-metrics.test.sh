#!/usr/bin/env bash
# Tests for sessionend-metrics.sh: one metrics row per session, replaced on re-run.
#
# Usage: bash tools/claude/hooks/sessionend-metrics.test.sh
# NOTE: no `set -e` — the test counts failures and must reach the end.
set -uo pipefail

HOOK="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/sessionend-metrics.sh"
command -v jq >/dev/null || { echo "jq required"; exit 2; }
command -v python3 >/dev/null || { echo "python3 required"; exit 2; }

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }

SID=aaaabbbb-1111-2222-3333-444455556666
OUT="$(mktemp -d)/sessions.jsonl"
T="$(mktemp)"
{
  jq -nc --arg s "$SID" '{type:"user",sessionId:$s,timestamp:"2026-10-29T00:00:00Z",message:{role:"user",content:"сделай"}}'
  jq -nc --arg s "$SID" '{type:"assistant",sessionId:$s,message:{role:"assistant",model:"m1",content:[{type:"text",text:"Делаю."},{type:"tool_use",name:"Bash",input:{command:"ls"}}],usage:{input_tokens:10,output_tokens:5}}}'
  jq -nc --arg s "$SID" '{type:"user",sessionId:$s,message:{role:"user",content:[{type:"tool_result",tool_use_id:"t",content:"ok"}]}}'
  jq -nc --arg s "$SID" '{type:"assistant",sessionId:$s,message:{role:"assistant",model:"m1",content:[{type:"text",text:"✔ done: готово"}],usage:{input_tokens:10,output_tokens:5}}}'
} > "$T"

run() { jq -nc --arg s "$SID" --arg t "$T" '{session_id:$s,transcript_path:$t}' | CLAUDE_METRICS_FILE="$OUT" "$HOOK"; }

printf '\n== first run writes one row ==\n'
run
[[ -f "$OUT" ]] && ok "file created" || bad "file created"
[[ "$(wc -l < "$OUT" | tr -d ' ')" == 1 ]] && ok "one row" || bad "one row" "$(wc -l < "$OUT") rows"
[[ "$(jq -r .sid "$OUT")" == aaaabbbb ]] && ok "row carries sid8" || bad "row carries sid8" "$(jq -c . "$OUT")"
[[ "$(jq -r .tool_calls "$OUT")" == 1 ]] && ok "metrics computed" || bad "metrics computed"

printf '\n== re-run replaces, other sessions stay ==\n'
printf '{"sid":"other123","tool_calls":9}\n' >> "$OUT"
run
[[ "$(wc -l < "$OUT" | tr -d ' ')" == 2 ]] && ok "still one row per session" || bad "still one row per session" "$(wc -l < "$OUT") rows"
grep -q other123 "$OUT" && ok "other session's row kept" || bad "other session's row kept"

printf '\n== missing transcript is a silent no-op ==\n'
before="$(wc -l < "$OUT")"
jq -nc --arg s "$SID" '{session_id:$s,transcript_path:"/nonexistent.jsonl"}' | CLAUDE_METRICS_FILE="$OUT" "$HOOK"
[[ $? -eq 0 && "$(wc -l < "$OUT")" == "$before" ]] && ok "no-op, exit 0" || bad "no-op, exit 0"

rm -f "$T" "$OUT"; rmdir "$(dirname "$OUT")"
printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
