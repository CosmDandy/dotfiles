#!/usr/bin/env zsh
set -eu
root=${0:A:h:h:h}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME=$tmp
mkdir -p "$HOME/.devpod/contexts/default/workspaces"
source "$root/tools/zsh/conf.d/devpod.zsh"
_dp_cache_dir
print -r -- old > "$DP_SNAPSHOT"
_dp_snapshot_refresh
[[ -f $DP_SNAPSHOT && ! -s $DP_SNAPSHOT ]]
[[ -z $(_dp_rows "$DP_SNAPSHOT") ]]
print -r -- old > "$tmp/base"
_dp_refresh_async "$tmp/fresh"
"$root/tools/devpod/await-rows.zsh" "$tmp/fresh" "$tmp/base" 5 > "$tmp/result"
[[ ! -s $tmp/base && ! -s $tmp/result ]]
print -r -- old > "$DP_SNAPSHOT"
mkdir "$HOME/.devpod/contexts/default/workspaces/broken"
print -r -- '{' > "$HOME/.devpod/contexts/default/workspaces/broken/workspace.json"
if _dp_snapshot_refresh; then exit 1; fi
[[ $(< "$DP_SNAPSHOT") == old ]]
