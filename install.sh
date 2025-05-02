#!/usr/bin/env zsh

# Установка Nix
if ! command -v nix &>/dev/null; then
  echo "Installing Nix..."
  curl -L https://nixos.org/nix/install | sh
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Устанавливаем пакеты через nix
packages=(
  python313
  starship
  fd
  ripgrep
  lua
  luarocks
  nodejs
  neovim
  eza
  tmux
  zellij
  btop
  lazygit
  lazydocker
  superfile
)
# devpod

print_section() {
  local message="$*"
  printf '%0.s~' {1..70}; echo
  echo "$message"
  printf '%0.s~' {1..70}; echo
}

for package in "${packages[@]}"; do
  print_section "Installing package ${package}"
  nix-env -iA nixpkgs.$package
done

# Создаем символьные ссылки
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME"

print_section "Create symbolic links and dirs"
create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    echo "Created dir ${dir}"
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

dirs=(
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
  "$PWD/nvim:$XDG_CONFIG_HOME/nvim"
  "$PWD/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$PWD/lazygit/conf.yml:$XDG_CONFIG_HOME/lazygit/conf.yml" # TODO: доделать конфиг
  "$PWD/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$PWD/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  )

create_directories "${dirs[@]}"
create_symlinks "${links[@]}"

print_section "Installing zinit"
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search
zinit light zdharma-continuum/fast-syntax-highlighting

print_section "Installing nvim plugins"
nvim --headless "+Lazy! sync" "+TSUpdateSync" +qa

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global
