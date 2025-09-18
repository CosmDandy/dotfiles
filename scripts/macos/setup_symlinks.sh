#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

export XDG_CONFIG_HOME="$HOME/.config"
dirs=(
  "$XDG_CONFIG_HOME"
  "$XDG_CONFIG_HOME/ghostty"
  "$XDG_CONFIG_HOME/atuin"
  "$XDG_CONFIG_HOME/btop"
  "$XDG_CONFIG_HOME/lazygit"
  "$XDG_CONFIG_HOME/superfile"
  "$HOME/Library/Application Support/Cursor/User/"
  "$HOME/Library/Application Support/Code/User/"
  "$HOME/.zsh/completions"
)

links=(
  "$PWD/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$PWD/zsh/.zprofile:$HOME/.zprofile"
  "$PWD/zsh/.zshrc:$HOME/.zshrc"
  "$PWD/zsh/completions:$HOME/.zsh/completions"
  "$PWD/git/.gitignore_global:$HOME/.gitignore_global"
  "$PWD/git/.gitconfig:$HOME/.gitconfig"
  "$PWD/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$PWD/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$PWD/nvim:$XDG_CONFIG_HOME/nvim"
  "$PWD/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$PWD/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$PWD/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  "$PWD/ghostty/config:$XDG_CONFIG_HOME/ghostty/config"
  "$PWD/vscode/settings.json:$HOME/Library/Application Support/Cursor/User/settings.json"
  "$PWD/vscode/keybindings.json:$HOME/Library/Application Support/Cursor/User/keybindings.json"
  "$PWD/vscode/settings.json:$HOME/Library/Application Support/Code/User/settings.json"
  "$PWD/vscode/keybindings.json:$HOME/Library/Application Support/Code/User/keybindings.json"
  "$PWD/leader_key/config.json:$HOME/Library/Application Support/Leader Key/config.json"
  "$PWD/aerospace/.aerospace.toml:$HOME/.aerospace.toml"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

# print_section "Copy Graphite.bundle"
# sudo cp -R "$PWD/keymap/Graphite.bundle" "/Library/Keyboard Layouts/Graphite.bundle"
