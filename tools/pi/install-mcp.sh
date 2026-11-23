#!/usr/bin/env bash
set -euo pipefail

defaults=$1
target=$2

umask 077
mkdir -p -- "$(dirname -- "$target")"
tmp=$(mktemp -- "$target.tmp.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT

snapshot=
expected=0
if [[ -e "$target" ]]; then
  snapshot=$(< "$target")
  expected=1
fi

# Merge by server name so user URLs, headers, disabled servers and unrelated settings survive.
printf '%s\n' "$snapshot" | jq -es --argjson expected "$expected" --slurpfile defaults "$defaults" '
  def config: type == "object"
    and (if has("mcpServers") then (.mcpServers | type == "object") else true end)
    and (any(..; type == "number" and (isnan or isinfinite)) | not);
  if ($defaults | length) != 1 or ($defaults[0].mcpServers | type != "object")
    or length != $expected or ($expected == 1 and (.[0] | config | not))
    then error("Invalid Pi MCP configuration")
    else (.[0] // {}) | .mcpServers = ($defaults[0].mcpServers + (.mcpServers // {}))
  end
' > "$tmp"

if [[ -f "$target" ]] && jq -es 'length == 2 and .[0] == .[1]' "$target" "$tmp" >/dev/null; then
  exit 0
fi
if [[ -L "$target" ]]; then
  printf 'Pi MCP: refusing to replace symlink %s\n' "$target" >&2
  exit 1
fi
if [[ -e "$target" ]]; then
  if [[ $expected == 0 || $(< "$target") != "$snapshot" ]]; then
    printf 'Pi MCP: %s changed during activation; not replacing it\n' "$target" >&2
    exit 1
  fi
elif [[ $expected == 1 ]]; then
  printf 'Pi MCP: %s was removed during activation; not recreating it\n' "$target" >&2
  exit 1
fi
mv -f -- "$tmp" "$target"
