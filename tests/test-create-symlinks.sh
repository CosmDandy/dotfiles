#!/usr/bin/env zsh
# Unit test for create_symlinks (platform/common.sh): backup + idempotency.
set -e

source "${0:A:h}/../platform/common.sh"

tmp=$(mktemp -d)
mkdir -p "$tmp/src"
echo "source-content" > "$tmp/src/file"
echo "pre-existing"    > "$tmp/target"   # real file → must be backed up

# 1st run: backs up real file, creates symlink
create_symlinks "$tmp/src/file:$tmp/target" >/dev/null
[[ -L "$tmp/target" && "$(readlink "$tmp/target")" == "$tmp/src/file" ]] \
  || { echo "FAIL: symlink not created"; exit 1; }
[[ "$(cat "$tmp/target.before-dotfiles")" == "pre-existing" ]] \
  || { echo "FAIL: real file not backed up"; exit 1; }

# 2nd run: idempotent — reports up to date, no double backup
out="$(create_symlinks "$tmp/src/file:$tmp/target")"
[[ "$out" == *"up to date"* ]] || { echo "FAIL: not idempotent: $out"; exit 1; }
[[ ! -e "$tmp/target.before-dotfiles.before-dotfiles" ]] \
  || { echo "FAIL: created a duplicate backup on rerun"; exit 1; }

rm -r "$tmp"
echo "PASS: create_symlinks backup + idempotency"
