#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# ===============================
# Bootstrap чистой машины (headless-совместимо, идемпотентно)
# ===============================

# Xcode CLT: без него нет git/компиляторов; GUI-запрос в headless невозможен,
# поэтому ставим через softwareupdate (label на новых macOS — с пробелом:
# "Command Line Tools for Xcode 26.5-26.5")
if ! xcode-select -p &>/dev/null; then
  print_section "Installing Xcode Command Line Tools"
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  CLT_LABEL=$(softwareupdate -l 2>/dev/null | grep '^\* Label: Command Line Tools' | sed 's/^\* Label: //' | tail -1)
  [[ -n "$CLT_LABEL" ]] || { echo "CLT label не найден в softwareupdate -l"; exit 1; }
  sudo softwareupdate -i "$CLT_LABEL" --agree-to-license
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi

# Rosetta 2: нужна Intel-каскам (amneziavpn); без неё brew bundle валит
# всю активацию nix-darwin
if [[ "$(uname -m)" == "arm64" ]] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  print_section "Installing Rosetta 2"
  sudo softwareupdate --install-rosetta --agree-to-license
fi

# Сабмодули как можно раньше: private (ssh/rbw-конфиги для симлинков ниже),
# tools/claude/custom (симлинки ~/.claude/*). Без ssh-ключей — мягкий скип.
print_section "Initializing submodules"
git -C "$DOTFILES_ROOT" submodule update --init --recursive \
  || echo "warn: submodules не подтянулись (нет ssh-ключей?) — приватные симлинки будут битыми до повторного запуска"

# ===============================
# Порядок важен: darwin-rebuild внутри install-nix.sh прогоняет brew bundle,
# поэтому к этому моменту brew уже должен стоять (иначе активация падает с
# exit 2), а симлинки — быть на месте (brew bundle читает ~/.homebrew/trust.json).
# install-extra.sh и setup-devpod.sh настраивают приложения и devpod CLI,
# которые ставятся касками из того же brew bundle, — только после него.
# ===============================
"$DOTFILES_ROOT/platform/macos/install-brew.sh"

# brew в PATH для остальных суб-скриптов: на настроенной машине это делает
# .zprofile login-шелла, на свежей — некому (setup-devpod.sh иначе не найдёт devpod)
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

"$DOTFILES_ROOT/platform/macos/setup-symlinks.sh"

"$DOTFILES_ROOT/platform/macos/install-nix.sh"

"$DOTFILES_ROOT/platform/macos/install-extra.sh"

"$DOTFILES_ROOT/platform/macos/setup-devpod.sh"

print_section "Applying OrbStack configuration"
"$DOTFILES_ROOT/tools/orbstack/apply.sh"

print_section "Installing Claude Code (native, self-updating binary)"
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

print_section "Installing Claude Code MCP servers"
if [[ -f "$DOTFILES_ROOT/tools/claude/custom/install.sh" ]]; then
  "$DOTFILES_ROOT/tools/claude/custom/install.sh"
else
  echo "warn: tools/claude/custom пуст (сабмодуль не подтянут) — MCP пропущены"
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
