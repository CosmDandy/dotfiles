#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

print_section "Creating symbolic links"
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
  "$HOME/.claude"
)

links=(
  "$PWD/tools/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$PWD/tools/zsh/.zprofile:$HOME/.zprofile"
  "$PWD/tools/zsh/.zshrc:$HOME/.zshrc"
  "$PWD/tools/zsh/.hushlogin:$HOME/.hushlogin"
  "$PWD/tools/zsh/completions:$HOME/.zsh/completions"
  "$PWD/tools/git/.gitignore_global:$HOME/.gitignore_global"
  "$PWD/tools/git/.gitconfig:$HOME/.gitconfig"
  "$PWD/tools/lazygit/config.yml:$XDG_CONFIG_HOME/lazygit/config.yml"
  "$PWD/tools/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$PWD/tools/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$PWD/tools/nvim:$XDG_CONFIG_HOME/nvim"
  "$PWD/tools/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$PWD/tools/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$PWD/tools/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  "$PWD/tools/ghostty/config:$XDG_CONFIG_HOME/ghostty/config"
  "$PWD/tools/vscode/settings.json:$HOME/Library/Application Support/Cursor/User/settings.json"
  "$PWD/tools/vscode/keybindings.json:$HOME/Library/Application Support/Cursor/User/keybindings.json"
  "$PWD/tools/vscode/settings.json:$HOME/Library/Application Support/Code/User/settings.json"
  "$PWD/tools/vscode/keybindings.json:$HOME/Library/Application Support/Code/User/keybindings.json"
  "$PWD/tools/leader_key/config.json:$HOME/Library/Application Support/Leader Key/config.json"
  "$PWD/tools/aerospace/.aerospace.toml:$HOME/.aerospace.toml"
  "$PWD/tools/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "$PWD/tools/claude/settings.json:$HOME/.claude/settings.json"
  "$HOME/.dotfiles-private/ssh/config:$HOME/.ssh/config"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

# print_section "Copy Graphite.bundle"
# sudo cp -R "$PWD/assets/keymap/Graphite.bundle" "/Library/Keyboard Layouts/Graphite.bundle"
