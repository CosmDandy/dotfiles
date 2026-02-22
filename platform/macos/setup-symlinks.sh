#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

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
  "$HOME/.lnav/configs/default"
)

links=(
  "$DOTFILES_ROOT/tools/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$DOTFILES_ROOT/tools/zsh/.zprofile:$HOME/.zprofile"
  "$DOTFILES_ROOT/tools/zsh/.zshrc:$HOME/.zshrc"
  "$DOTFILES_ROOT/tools/zsh/.hushlogin:$HOME/.hushlogin"
  "$DOTFILES_ROOT/tools/zsh/completions:$HOME/.zsh/completions"
  "$DOTFILES_ROOT/tools/git/.gitignore_global:$HOME/.gitignore_global"
  "$DOTFILES_ROOT/tools/git/.gitconfig:$HOME/.gitconfig"
  "$DOTFILES_ROOT/tools/lazygit/config.yml:$XDG_CONFIG_HOME/lazygit/config.yml"
  "$DOTFILES_ROOT/tools/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$DOTFILES_ROOT/tools/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$DOTFILES_ROOT/tools/nvim:$XDG_CONFIG_HOME/nvim"
  "$DOTFILES_ROOT/tools/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$DOTFILES_ROOT/tools/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$DOTFILES_ROOT/tools/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  "$DOTFILES_ROOT/tools/ghostty/config:$XDG_CONFIG_HOME/ghostty/config"
  "$DOTFILES_ROOT/tools/vscode/settings.json:$HOME/Library/Application Support/Cursor/User/settings.json"
  "$DOTFILES_ROOT/tools/vscode/keybindings.json:$HOME/Library/Application Support/Cursor/User/keybindings.json"
  "$DOTFILES_ROOT/tools/vscode/settings.json:$HOME/Library/Application Support/Code/User/settings.json"
  "$DOTFILES_ROOT/tools/vscode/keybindings.json:$HOME/Library/Application Support/Code/User/keybindings.json"
  "$DOTFILES_ROOT/tools/leader-key/config.json:$HOME/Library/Application Support/Leader Key/config.json"
  "$DOTFILES_ROOT/tools/aerospace/.aerospace.toml:$HOME/.aerospace.toml"
  "$DOTFILES_ROOT/tools/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "$DOTFILES_ROOT/tools/claude/settings.json:$HOME/.claude/settings.json"
  "$DOTFILES_ROOT/tools/claude/statusline.sh:$HOME/.claude/statusline.sh"
  "$DOTFILES_ROOT/tools/claude/agents:$HOME/.claude/agents"
  "$DOTFILES_ROOT/tools/claude/commands:$HOME/.claude/commands"
  "$DOTFILES_ROOT/tools/claude/skills:$HOME/.claude/skills"
  "$DOTFILES_ROOT/tools/claude/rules:$HOME/.claude/rules"
  "$DOTFILES_ROOT/tools/lnav/config.json:$HOME/.lnav/configs/default/config.json"
  "$HOME/.dotfiles-private/ssh/config:$HOME/.ssh/config"
  "$DOTFILES_ROOT/private/git/.gitconfig.local:$HOME/.gitconfig.local"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

# print_section "Copy Graphite.bundle"
# sudo cp -R "$PWD/assets/keymap/Graphite.bundle" "/Library/Keyboard Layouts/Graphite.bundle"
