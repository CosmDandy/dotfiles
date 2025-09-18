#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

print_section "Installing Nix"
curl -L https://nixos.org/nix/install | sh

if [ -e '/home/vscode/.nix-profile/etc/profile.d/nix.sh' ]; then
  . /home/vscode/.nix-profile/etc/profile.d/nix.sh
fi

bash $SCRIPT_DIR/scripts/devcontainer/setup_symlinks.sh

print_section "Activating Nix development environment and installing nvim plugins"
nix develop $SCRIPT_DIR/nix --impure --accept-flake-config --extra-experimental-features "nix-command flakes" --command bash -c "nvim --headless '+Lazy! sync' '+TSUpdateSync' +qa"

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global

print_section "Installing zinit"
bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

print_section "Installing zsh plugins"
zsh -c "
source ~/.local/share/zinit/zinit.git/zinit.zsh
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search
zinit light zdharma-continuum/fast-syntax-highlighting
"

print_section "Install complete"
