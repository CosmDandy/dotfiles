#!/usr/bin/env zsh

set -e

# Suppress debconf warnings in non-interactive containers
export DEBIAN_FRONTEND=noninteractive

# Resolve the repository root and export it for every child script.
export DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"

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
