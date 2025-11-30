#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

"$SCRIPT_DIR/scripts/macos/install_nix.sh"

"$SCRIPT_DIR/scripts/macos/install_brew.sh"

"$SCRIPT_DIR/scripts/macos/install_extra.sh"

"$SCRIPT_DIR/scripts/macos/setup_devpod.sh"

"$SCRIPT_DIR/scripts/macos/setup_symlinks.sh"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
