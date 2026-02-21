#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

"$DOTFILES_ROOT/platform/macos/install-nix.sh"

"$DOTFILES_ROOT/platform/macos/install-brew.sh"

"$DOTFILES_ROOT/platform/macos/install-extra.sh"

"$DOTFILES_ROOT/platform/macos/setup-devpod.sh"

"$DOTFILES_ROOT/platform/macos/setup-symlinks.sh"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
