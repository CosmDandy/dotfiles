#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

"$SCRIPT_DIR/install-nix.sh"

"$SCRIPT_DIR/install-brew.sh"

"$SCRIPT_DIR/install-extra.sh"

"$SCRIPT_DIR/setup-devpod.sh"

"$SCRIPT_DIR/setup-symlinks.sh"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
