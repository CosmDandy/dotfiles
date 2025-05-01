#!/usr/bin/env zsh

# xcode-tools
xcode-select --install
softwareupdate --install-rosetta

# homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env

# Installing packages
packages=(
  iperf3
  speedtest-cli
  duf
  dua-cli
  mosh
)

for package in "${packages[@]}"; do
  printf '%0.s~' {1..70}
  echo "Installing packages ${package}"
  printf '%0.s~' {1..70}
  nix-env -iA nixpkgs.$package
done

# Installing casks
casks=(
  ghostty
  raycast
  nikitabobko/tap/aerospace
  utm
)

for cask in "${casks[@]}"; do
  printf '%0.s~' {1..70}
  echo "Installing cask $cask..."
  brew install --cask "$cask"
  printf '%0.s~' {1..70}
done
brew install secretive

chsh -s $(which zsh)
source ~/.zshrc
