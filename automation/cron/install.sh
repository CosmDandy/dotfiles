#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# NOTE: the pull runs first and on its own line. Every other entry executes a
# script out of this clone, and nothing else ever updated it: the host ran
# August's devpod-update.sh into late October, missing the restart-policy fix
# that existed only in the repo. Five minutes before the earliest job, so no
# script is rewritten while it runs. --ff-only: a rewritten upstream history
# fails here, loudly in syslog, instead of being merged into a mess.
# The remote is https (set by hand on the host): cron has no ssh agent to fetch
# a git@ URL with, and the repository is public.
CRON_ENTRIES="
# --- dotfiles automation ---
55 1 * * * git -C $REPO_DIR pull --ff-only -q --no-recurse-submodules 2>&1 | logger -t dotfiles-pull
0 2 * * 0 $SCRIPT_DIR/apt-upgrade.sh 2>&1 | logger -t apt-upgrade
30 2 * * 0 $SCRIPT_DIR/devpod-nix-gc.sh 2>&1 | logger -t devpod-nix-gc
40 2 * * * $SCRIPT_DIR/docker-cleanup.sh 2>&1 | logger -t docker-cleanup
50 2 * * * $SCRIPT_DIR/devpod-update.sh 2>&1 | logger -t devpod-update
# --- end dotfiles automation ---
"

# Remove old entries and add new ones
EXISTING=$(crontab -l 2>/dev/null || true)
EXISTING=$(echo "$EXISTING" | sed '/# --- dotfiles automation ---/,/# --- end dotfiles automation ---/d')
echo "${EXISTING}${CRON_ENTRIES}" | crontab -

echo "Crontab installed:"
crontab -l | grep -A 10 "dotfiles automation"
