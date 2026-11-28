#!/usr/bin/env bash
set -euo pipefail

defaults=$1
settings=$2
tmp=$(mktemp "${settings}.subagents.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq -e --slurpfile defaults "$defaults" '
  if type != "object" or (.subagents != null and (.subagents | type) != "object")
  then error("Expected a Pi settings object")
  else .
  end
  | $defaults[0].subagents as $managed
  | ($managed * (.subagents // {})
     # Migrate only the old managed tool lists.
     | reduce ("scout", "reviewer", "oracle") as $role (.;
         if .agentOverrides[$role].tools == ["read", "grep", "find", "ls"]
         then .agentOverrides[$role].tools = $managed.agentOverrides[$role].tools
         else .
         end)) as $subagents
  | .subagents = $subagents
  | if (.compaction.modelOverrides | type) == "object" then
      # Remove only the old managed reserves; this settings file may also be opened by stock Pi.
      .compaction.modelOverrides |= with_entries(
        (.key | sub("^openai-codex/"; "")) as $id
        | (if ($id | IN("gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-6-astra", "gpt-6-luna", "gpt-6-sol", "gpt-6.2-astra")) then 95200
           elif ($id | test("^gpt-6\\.1-(sol|terra)$")) then 175000
           elif $id == "gpt-6.2-sol" then 200000 else null end) as $old
        | if (.key | startswith("openai-codex/")) and $old != null and .value.reserveTokens == $old
          then .value |= del(.reserveTokens) | select(.value != {}) else . end)
      | if .compaction.modelOverrides == {} then del(.compaction.modelOverrides) else . end
    else . end
' "$settings" > "$tmp"
if jq -e --slurpfile updated "$tmp" '. == $updated[0]' "$settings" >/dev/null; then
  exit 0
fi
chmod 0600 "$tmp"
mv "$tmp" "$settings"
