#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Pin the container job at install time: a host pull must not silently change
# which operations cron is allowed to run inside every workspace.
SYNC="$HOME/.local/libexec/dotfiles/devpod-update.sh"
install -d "$(dirname "$SYNC")"
install -m 0755 "$SCRIPT_DIR/devpod-update.sh" "$SYNC"

# The remote is https (set by hand on the host): cron has no ssh agent to fetch
# a git@ URL with, and the repository is public.
CRON_ENTRIES="
# --- dotfiles automation ---
55 1 * * * git -C $REPO_DIR pull --ff-only -q --no-recurse-submodules 2>&1 | logger -t dotfiles-pull
0 2 * * 0 $SCRIPT_DIR/apt-upgrade.sh 2>&1 | logger -t apt-upgrade
40 2 * * * $SCRIPT_DIR/docker-cleanup.sh 2>&1 | logger -t docker-cleanup
50 2 * * * $SYNC 2>&1 | logger -t devpod-dotfiles-pull
# --- end dotfiles automation ---
"

# Remove old entries and add new ones
EXISTING=$(crontab -l 2>/dev/null || true)
EXISTING=$(echo "$EXISTING" | sed '/# --- dotfiles automation ---/,/# --- end dotfiles automation ---/d')
echo "${EXISTING}${CRON_ENTRIES}" | crontab -

echo "Crontab installed:"
crontab -l | grep -A 10 "dotfiles automation"
