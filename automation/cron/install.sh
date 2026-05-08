#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CRON_ENTRIES="
# --- dotfiles automation ---
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
