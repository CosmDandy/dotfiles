#!/usr/bin/env bash
set -euo pipefail

script=$(cd "$(dirname "$0")/.." && pwd)/devpod-update.sh
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
export HOME="$d/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$d/bin"
git init -qb main "$d/upstream"
git -C "$d/upstream" -c user.name=test -c user.email=test@example.org commit -qm first --allow-empty
git clone -q "$d/upstream" "$HOME/dotfiles"
git config --global "url.file://$d/upstream.insteadOf" https://github.com/CosmDandy/dotfiles.git
git -C "$d/upstream" -c user.name=test -c user.email=test@example.org commit -qm second --allow-empty
first=$(git -C "$HOME/dotfiles" rev-parse HEAD)
latest=$(git -C "$d/upstream" rev-parse HEAD)
origin=$(git -C "$HOME/dotfiles" remote get-url origin)
printf '%s\n' '#!/bin/bash' 'set -eu' \
  'case "$*" in' \
  '"ps --filter label=devpod.user --format {{.Names}}") echo running;;' \
  '"exec -u cosmdandy -e HOME=/home/cosmdandy running sh -ec "*) shift 6; exec "$@";;' \
  '*) echo "Unexpected docker invocation: $*" >&2; exit 1;; esac' > "$d/bin/docker"
chmod +x "$d/bin/docker"
export PATH="$d/bin:$PATH"
cd "$HOME/dotfiles"
touch local-work
bash "$script"; [[ $(git rev-parse HEAD) == "$first" && -f local-work ]]
rm local-work
git switch -qc topic
bash "$script"; [[ $(git rev-parse HEAD) == "$first" ]]
git switch -q main
bash "$script"; [[ $(git rev-parse HEAD) == "$latest" && $(git remote get-url origin) == "$origin" ]]
bash "$script"; [[ $(git rev-parse HEAD) == "$latest" ]]
echo 'PASS: running only, dirty checkout, topic branch, fast-forward, origin preserved, repeat sync'
