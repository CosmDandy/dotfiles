#!/bin/bash

# Ставим brew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Ставим starship
curl -sS https://starship.rs/install.sh | sh

# Устанавливаем необходимые пакеты
packages=(
  'gcc'
  # Prompt
  'starship'
  # Nvim
  'fd'
  'ripgrep'
  'lua'
  'luarocks'
  'npm'
  'nvim'
  # Утилиты
  'eza'
  'tmux'
  'btop'
)

build_from_source_packages=(
  'lazygit'
  'lazydocker'
  'superfile'
)

# Установка обычных пакетов
for package in "${packages[@]}"; do
  echo "Installing $package..."
  brew install "$package"
done

# Установка пакетов с опцией --build-from-source
for package in "${build_from_source_packages[@]}"; do
  echo "Installing $package from source..."
  brew install --build-from-source "$package"
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
  "$PWD/lazygit/conf.yml:$XDG_CONFIG_HOME/lazygit/conf.yml"
  "$PWD/superfile/config.toml:$XDG_CONFIG_HOME/superfile/config.toml"
  "$PWD/superfile/hotkeys.toml:$XDG_CONFIG_HOME/superfile/hotkeys.toml"
  )

create_directories "${dirs[@]}"
create_symlinks "${links[@]}"
