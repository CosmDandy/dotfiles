#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Порядок важен: darwin-rebuild внутри install-nix.sh прогоняет brew bundle,
# поэтому к этому моменту brew уже должен стоять (иначе активация падает с
# exit 2), а симлинки — быть на месте (brew bundle читает ~/.homebrew/trust.json).
# install-extra.sh и setup-devpod.sh настраивают приложения и devpod CLI,
# которые ставятся касками из того же brew bundle, — только после него.
"$DOTFILES_ROOT/platform/macos/install-brew.sh"

"$DOTFILES_ROOT/platform/macos/setup-symlinks.sh"

"$DOTFILES_ROOT/platform/macos/install-nix.sh"

"$DOTFILES_ROOT/platform/macos/install-extra.sh"

"$DOTFILES_ROOT/platform/macos/setup-devpod.sh"

print_section "Applying OrbStack configuration"
"$DOTFILES_ROOT/tools/orbstack/apply.sh"

print_section "Installing Claude Code (native, self-updating binary)"
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

print_section "Initializing submodules"
git -C "$DOTFILES_ROOT" submodule update --init --recursive

print_section "Installing Claude Code MCP servers"
"$DOTFILES_ROOT/tools/claude/custom/install.sh"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
