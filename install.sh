#!/usr/bin/env zsh

set -e

# Suppress debconf warnings in non-interactive containers
export DEBIAN_FRONTEND=noninteractive

# Resolve the repository root and export it for every child script.
export DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Every run is recorded. A provisioning run is long, mostly unattended and
# frequently watched through a pipe that shows nothing — and when it does fail,
# the interesting line scrolled past twenty minutes ago or went to a terminal
# nobody kept. The log is written whether or not anyone is looking.
# NOTE: process substitution rather than a wrapper script, so a failure inside a
# child still reaches the terminal live instead of appearing only at the end.
# NOTE: no ANSI stripping — BSD and GNU sed disagree on line buffering, and a
# half-buffered log is worse than a coloured one. `less -R` or `sed` after the
# fact both read it fine.
DOTFILES_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
mkdir -p "$DOTFILES_LOG_DIR"
export DOTFILES_LOG="$DOTFILES_LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
ln -sfn "$DOTFILES_LOG" "$DOTFILES_LOG_DIR/install-last.log"
exec > >(tee -a "$DOTFILES_LOG") 2>&1

# Header first: a log that does not say which commit, profile and host produced
# it cannot be compared against another run, which is the only thing anyone ever
# wants from it.
{
  echo "date:    $(date -Iseconds)"
  echo "host:    $(hostname) ($(uname -sm))"
  echo "user:    $(whoami)"
  echo "repo:    $DOTFILES_ROOT @ $(git -C "$DOTFILES_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'not a git tree')"
  echo "profile: ${PROFILE:-<from marker>}"
  echo "log:     $DOTFILES_LOG"
}

# Keep the last 10 runs. Unbounded logs in $HOME are their own kind of mess.
ls -1t "$DOTFILES_LOG_DIR"/install-2*.log 2>/dev/null | tail -n +11 | xargs -r rm -f

# NOTE: the calls go through $DOTFILES_ROOT rather than a relative path — it was computed
# above and then ignored, so running from anywhere but the repo root failed with "no such
# file". It only ever worked because the README tells you to cd first.
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 Detected macOS"
  "$DOTFILES_ROOT/platform/macos/install.sh"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  echo "🐧 Detected Linux"
  "$DOTFILES_ROOT/platform/linux/install.sh"
else
  echo "❌ Unsupported OS: $OSTYPE"
  exit 1
fi

echo "полный лог: $DOTFILES_LOG"
