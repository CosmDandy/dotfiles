#!/usr/bin/env zsh

set -e

RED='\033[0;31m'
NC='\033[0m'

print_section() {
  local message="$*"
  printf '%0.s~' {1..70}; echo
  echo -e "${RED}$message${NC}"
  printf '%0.s~' {1..70}; echo
}

create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    echo "Created directory ${dir}"
  done
}

create_symlinks() {
  local items=("$@")
  for item in "${items[@]}"; do
    IFS=':' read -r source target <<<"$item"
    rm -rf "$target"
    ln -s "$source" "$target"
    echo "Created symlink for $source"
  done
}

print_section "Installing mise(for all lang)"
curl https://mise.run | sh
echo "eval \"\$(/home/vscode/.local/bin/mise activate zsh)\"" >> "/home/vscode/.zshrc"
eval "$($HOME/.local/bin/mise activate zsh)"

print_section "Installing rust" 
mise install rust@latest
print_section "Installing go"
mise install go@latest

print_section "Installing uv(python)"
curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.14

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
  )

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

print_section "Installing zinit"
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search
zinit light zdharma-continuum/fast-syntax-highlighting

print_section "Installing tmux plugins"
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

print_section "Installing nvim plugins"
nvim --headless "+Lazy! sync" "+TSUpdateSync" +qa

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global
