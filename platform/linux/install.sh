#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

print_section "Installing uv"
curl -LsSf https://astral.sh/uv/install.sh | sh

print_section "Installing atuin"
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

# Установка Nix
if ! command -v nix &>/dev/null; then
  print_section "Installing Nix"
  curl -L https://nixos.org/nix/install | sh
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Устанавливаем пакеты через nix
packages=(
  starship
  fd
  ripgrep
  lua
  luarocks
  nodejs
  neovim
  eza
  tmux
  btop
  lazygit
  lazydocker
)

for package in "${packages[@]}"; do
  print_section "Installing package ${package}"
  nix-env -iA nixpkgs.$package
done

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

# Корень репозитория (два уровня вверх от platform/linux/)
REPO_ROOT="$SCRIPT_DIR/../.."

links=(
  "$REPO_ROOT/tools/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$REPO_ROOT/tools/zsh/.zprofile:$HOME/.zprofile"
  "$REPO_ROOT/tools/zsh/.zshrc:$HOME/.zshrc"
  "$REPO_ROOT/tools/zsh/completions:$HOME/.zsh/completions"
  "$REPO_ROOT/tools/git/.gitignore_global:$HOME/.gitignore_global"
  "$REPO_ROOT/tools/git/.gitconfig:$HOME/.gitconfig"
  "$REPO_ROOT/tools/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$REPO_ROOT/tools/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$REPO_ROOT/tools/nvim:$XDG_CONFIG_HOME/nvim"
  "$REPO_ROOT/tools/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$REPO_ROOT/tools/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$REPO_ROOT/tools/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  "$REPO_ROOT/tools/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "$REPO_ROOT/tools/claude/settings.json:$HOME/.claude/settings.json"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

print_section "Installing tmux plugins"
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

print_section "Installing nvim plugins"
nvim --headless "+Lazy! sync" "+TSUpdateSync" +qa

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global

print_section "Installing zinit"
bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search
zinit light zdharma-continuum/fast-syntax-highlighting

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECONDS}s"
