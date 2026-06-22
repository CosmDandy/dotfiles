#!/usr/bin/env bash
set -uo pipefail

# Reusable, non-sudo macOS cache cleanup.
# Safe to run manually (alias: clean) or from launchd.
# Does NOT touch containers/OrbStack or system nix generations (sudo).
# System nix generations are pruned by `updm` instead.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:/usr/local/bin:/usr/bin:/bin"

LOG_PREFIX="[cleanup-mac]"

echo "$LOG_PREFIX Homebrew cleanup..."
brew cleanup --prune=all 2>/dev/null || echo "$LOG_PREFIX brew skipped"

echo "$LOG_PREFIX npm cache clean..."
npm cache clean --force 2>/dev/null || echo "$LOG_PREFIX npm skipped"

echo "$LOG_PREFIX uv cache prune (unused only)..."
# --force: bypass the lock held by the always-on timing-mcp server.
# prune only removes unused archives, so the running server is safe.
UV_LOCK_TIMEOUT=10 uv cache prune --force 2>/dev/null || echo "$LOG_PREFIX uv skipped"

echo "$LOG_PREFIX nix user-profile GC..."
nix-collect-garbage -d 2>/dev/null || echo "$LOG_PREFIX nix skipped"

echo "$LOG_PREFIX Done"
