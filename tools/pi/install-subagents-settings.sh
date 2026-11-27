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
' "$settings" > "$tmp"
if jq -e --slurpfile updated "$tmp" '.subagents == $updated[0].subagents' "$settings" >/dev/null; then
  exit 0
fi
chmod 0600 "$tmp"
mv "$tmp" "$settings"
