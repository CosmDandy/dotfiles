#!/usr/bin/env zsh

# xcode-tools
xcode-select --install
softwareupdate --install-rosetta

# homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

. "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/$USER/channels/nixpkgs"

source ./install.sh

eval "$(/opt/homebrew/bin/brew shellenv)"

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# Installing packages
packages=(
  devpod
  iperf3
  speedtest-cli
)

for package in "${packages[@]}"; do
  print_section "Installing package ${package}"
  nix-env -iA nixpkgs.$package
done

# Installing casks
casks=(
  utm
  ghostty
  nikitabobko/tap/aerospace
)

for cask in "${casks[@]}"; do
  print_section "Installing cask $cask..."
  brew install --cask "$cask"
done
brew install secretive
brew install orbstack
brew install leader-key

dirs=(
  "$XDG_CONFIG_HOME/ghostty"
  )

links=(
  "$PWD/ghostty/config:$XDG_CONFIG_HOME/ghostty/config"
  "$PWD/vscode/settings.json:$HOME/Library/Application Support/Cursor/User/settings.json"
  "$PWD/vscode/keybindings.json:$HOME/Library/Application Support/Cursor/User/keybindings.json"
  "$PWD/vscode/settings.json:$HOME/Library/Application Support/Code/User/settings.json"
  "$PWD/vscode/keybindings.json:$HOME/Library/Application Support/Code/User/keybindings.json"
  "$PWD/leader_key/congig.json:$HOME/Library/Application Support/Leader Key/config.json"
  "$PWD/aerospace/.aerospace.toml:$HOME/.aerospace.toml"
  )

create_directories "${dirs[@]}"
create_symlinks "${links[@]}"

source ~/.zshrc
