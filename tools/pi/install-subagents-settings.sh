#!/usr/bin/env bash
set -euo pipefail

defaults=$1
settings=$2
if jq -e --slurpfile defaults "$defaults" '
  .subagents == ($defaults[0].subagents * (.subagents // {}))
' "$settings" >/dev/null; then
  exit 0
fi

tmp=$(mktemp "${settings}.subagents.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq -e --slurpfile defaults "$defaults" '
  if type != "object" or (.subagents != null and (.subagents | type) != "object")
  then error("Expected a Pi settings object")
  else .subagents = ($defaults[0].subagents * (.subagents // {}))
  end
' "$settings" > "$tmp"
chmod 0600 "$tmp"
mv "$tmp" "$settings"
