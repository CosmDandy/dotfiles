#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Bootstrap of a clean machine: headless-compatible and idempotent.

# NOTE: without Xcode CLT there is no git and no compilers, and the GUI prompt cannot
# appear headless — hence softwareupdate with an explicit label (which contains a space on
# recent macOS: "Command Line Tools for Xcode 26.5-26.5").
if ! xcode-select -p &>/dev/null; then
  print_section "Installing Xcode Command Line Tools"
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  CLT_LABEL=$(softwareupdate -l 2>/dev/null | grep '^\* Label: Command Line Tools' | sed 's/^\* Label: //' | tail -1)
  [[ -n "$CLT_LABEL" ]] || { echo "CLT label не найден в softwareupdate -l"; exit 1; }
  sudo softwareupdate -i "$CLT_LABEL" --agree-to-license
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi

# NOTE: Rosetta 2 is needed by Intel casks; without it brew bundle fails the whole
# nix-darwin activation.
if [[ "$(uname -m)" == "arm64" ]] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  print_section "Installing Rosetta 2"
  sudo softwareupdate --install-rosetta --agree-to-license
fi

# Submodules as early as possible: private holds the ssh/rbw configs the symlinks below
# point at, and tools/claude/custom holds ~/.claude/*. Soft skip without ssh keys.
print_section "Initializing submodules"
git -C "$DOTFILES_ROOT" submodule update --init --recursive \
  || echo "warn: submodules не подтянулись (нет ssh-ключей?) — приватные симлинки будут битыми до повторного запуска"

# NOTE: order matters — darwin-rebuild inside install-nix.sh runs brew bundle, so brew must
# already exist by then or the activation aborts with exit 2. Everything user-level
# (symlinks, devpod, orbstack, claude, MCP) is home-manager inside that same rebuild.
"$DOTFILES_ROOT/platform/macos/install-brew.sh"

# brew on PATH for the remaining sub-scripts: on a configured machine .zprofile does this,
# on a fresh one there is nobody to.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# NOTE: brew bundle needs trust.json INSIDE darwin-rebuild, and the homebrew activation
# step runs BEFORE home-manager — so the first pass pre-seeds it by hand; the next switch
# moves these symlinks to *.hm-backup and installs its own.
print_section "Pre-seeding homebrew trust.json"
mkdir -p "$HOME/.homebrew" "$HOME/.config/homebrew"
for f in "$HOME/.homebrew/trust.json" "$HOME/.config/homebrew/trust.json"; do
  [[ -e "$f" || -L "$f" ]] || ln -s "$DOTFILES_ROOT/tools/homebrew/trust.json" "$f"
done

"$DOTFILES_ROOT/platform/macos/install-nix.sh"

"$DOTFILES_ROOT/platform/macos/install-extra.sh"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"

# TODO: make "sort by kind" the default on the desktop and in Finder windows
