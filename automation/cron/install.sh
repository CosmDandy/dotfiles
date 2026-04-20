#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CRON_ENTRIES="
# --- dotfiles automation ---
0 2 * * 0 $SCRIPT_DIR/apt-upgrade.sh >> logger -t apt-upgrade 2>&1
30 2 * * 0 $SCRIPT_DIR/devpod-nix-gc.sh >> logger -t devpod-nix-gc 2>&1
40 2 * * * $SCRIPT_DIR/docker-cleanup.sh >> logger -t docker-cleanup 2>&1
50 2 * * * $SCRIPT_DIR/devpod-update.sh >> logger -t devpod-update 2>&1
# --- end dotfiles automation ---
"

# Remove old entries and add new ones
EXISTING=$(crontab -l 2>/dev/null || true)
EXISTING=$(echo "$EXISTING" | sed '/# --- dotfiles automation ---/,/# --- end dotfiles automation ---/d')
echo "${EXISTING}${CRON_ENTRIES}" | crontab -

echo "Crontab installed:"
crontab -l | grep -A 10 "dotfiles automation"
