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

for package in "${packages[@]}"; do
  printf '%0.s~' {1..70}
  echo "Installing packages ${package}"
  printf '%0.s~' {1..70}
  nix-env -iA nixpkgs.$package
done

# Создаем символьные ссылки
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME"

create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
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
  )

links=(
  "$PWD/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$PWD/zsh/.zprofile:$HOME/.zprofile"
  "$PWD/zsh/.zshrc:$HOME/.zshrc"
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

ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

zinit light zsh-users/zsh-autosuggestions
zinit light zdharma-continuum/fast-syntax-highlighting

nvim --headless "+Lazy! sync" "+TSUpdateSync" +qa

git config --global core.excludesfile ~/.gitignore_global
