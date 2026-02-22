#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Установка Nix
if ! command -v nix &> /dev/null; then
  print_section "Installing Nix"
  curl -L https://nixos.org/nix/install | sh
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Загружаем Nix окружение если еще не загружено
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  source "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

print_section "Verifying Nix installation"
nix --version

# Создаем символьные ссылки
export XDG_CONFIG_HOME="$HOME/.config"

dirs=(
  "$XDG_CONFIG_HOME"
  "$XDG_CONFIG_HOME/atuin"
  "$XDG_CONFIG_HOME/btop"
  "$XDG_CONFIG_HOME/lazygit"
  "$XDG_CONFIG_HOME/superfile"
  "$HOME/.zsh/completions"
  "$HOME/.claude"
)

links=(
  "$DOTFILES_ROOT/tools/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$DOTFILES_ROOT/tools/zsh/.zprofile:$HOME/.zprofile"
  "$DOTFILES_ROOT/tools/zsh/.zshrc:$HOME/.zshrc"
  "$DOTFILES_ROOT/tools/zsh/completions:$HOME/.zsh/completions"
  "$DOTFILES_ROOT/tools/git/.gitignore_global:$HOME/.gitignore_global"
  "$DOTFILES_ROOT/tools/git/.gitconfig:$HOME/.gitconfig"
  "$DOTFILES_ROOT/tools/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$DOTFILES_ROOT/tools/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$DOTFILES_ROOT/tools/nvim:$XDG_CONFIG_HOME/nvim"
  "$DOTFILES_ROOT/tools/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$DOTFILES_ROOT/tools/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$DOTFILES_ROOT/tools/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  "$DOTFILES_ROOT/tools/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "$DOTFILES_ROOT/tools/claude/settings.json:$HOME/.claude/settings.json"
  "$DOTFILES_ROOT/tools/claude/statusline.sh:$HOME/.claude/statusline.sh"
  "$DOTFILES_ROOT/tools/claude/agents:$HOME/.claude/agents"
  "$DOTFILES_ROOT/tools/claude/commands:$HOME/.claude/commands"
  "$DOTFILES_ROOT/tools/claude/skills:$HOME/.claude/skills"
  "$DOTFILES_ROOT/tools/claude/rules:$HOME/.claude/rules"
  "$DOTFILES_ROOT/private/git/.gitconfig.local:$HOME/.gitconfig.local"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

print_section "Activating Nix development environment and installing nvim plugins"
cd "$SCRIPT_DIR"
nix develop "$SCRIPT_DIR#flake-linux" --impure --accept-flake-config --extra-experimental-features "nix-command flakes" --command bash -c "nvim --headless '+Lazy! sync' '+TSUpdate' +qa"

print_section "Installing tmux plugins"
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm 2>/dev/null || echo "TPM already installed"

# TODO: Разобраться с автоматической установкой Mason tools
# Проблема: команда зависает или не находит нужные команды в headless режиме
# Временное решение: установить вручную через :MasonToolsInstall после первого запуска nvim
# print_section "Installing Mason tools (LSP, linters, formatters)"
# nvim --headless "+lua require('mason-tool-installer').check_install(true)" +qa

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global

print_section "Installing zinit"
bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# Плагины zinit будут установлены автоматически при первом запуске zsh

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"
