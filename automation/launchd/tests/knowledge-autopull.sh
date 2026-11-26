#!/usr/bin/env bash
set -euo pipefail

script=$(cd "$(dirname "$0")/../scripts" && pwd)/knowledge-autopull.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL

git init -q -b master "$tmp/upstream"
printf 'initial\n' > "$tmp/upstream/note.md"
printf 'initial\n' > "$tmp/upstream/draft.md"
printf 'ignored.md\n' > "$tmp/upstream/.gitignore"
git -C "$tmp/upstream" add note.md draft.md .gitignore
git -C "$tmp/upstream" commit -qm initial
for name in unrelated tracked untracked ignored diverged wrong-branch; do
  git clone -q "$tmp/upstream" "$tmp/$name"
done
initial=$(git -C "$tmp/upstream" rev-parse HEAD)
printf 'incoming\n' > "$tmp/upstream/note.md"
printf 'incoming\n' > "$tmp/upstream/new.md"
printf 'incoming\n' > "$tmp/upstream/ignored.md"
git -C "$tmp/upstream" add -f note.md new.md ignored.md
git -C "$tmp/upstream" commit -qm upstream
incoming=$(git -C "$tmp/upstream" rev-parse HEAD)

pull() { /bin/bash "$script" "$@"; }
assert_head() { [[ $(git -C "$tmp/$1" rev-parse HEAD) == "$2" ]]; }
assert_refused() {
  local name=$1 file=$2
  printf 'local\n' > "$tmp/$name/$file"
  if pull "$tmp/$name"; then
    printf 'Expected %s to block the update\n' "$name" >&2
    exit 1
  fi
  assert_head "$name" "$initial"
  [[ $(< "$tmp/$name/$file") == local ]]
  if [[ $file != new.md ]]; then [[ ! -e "$tmp/$name/new.md" ]]; fi
  if [[ $name != ignored ]] && pull --dry-run "$tmp/$name"; then
    printf 'Expected the dry run to detect %s\n' "$name" >&2
    exit 1
  fi
}

printf 'local\n' > "$tmp/unrelated/draft.md"
pull --dry-run "$tmp/unrelated"
assert_head unrelated "$initial"
[[ $(< "$tmp/unrelated/note.md") == initial ]]
pull "$tmp/unrelated"
assert_head unrelated "$incoming"
[[ $(< "$tmp/unrelated/note.md") == incoming ]]
[[ $(< "$tmp/unrelated/draft.md") == local ]]

assert_refused tracked note.md
assert_refused untracked new.md
assert_refused ignored ignored.md

git -C "$tmp/diverged" commit -qm local --allow-empty
local_head=$(git -C "$tmp/diverged" rev-parse HEAD)
if pull "$tmp/diverged"; then exit 1; fi
assert_head diverged "$local_head"
git -C "$tmp/wrong-branch" switch -qc other
pull "$tmp/wrong-branch"
assert_head wrong-branch "$initial"
printf 'Autopull integration tests passed.\n'
