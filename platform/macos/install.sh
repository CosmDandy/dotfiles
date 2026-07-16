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
# exit 2). Всё пользовательское окружение (симлинки, devpod, orbstack,
# claude, MCP) — home-manager внутри того же darwin-rebuild.
# ===============================
"$DOTFILES_ROOT/platform/macos/install-brew.sh"

# brew в PATH для остальных суб-скриптов: на настроенной машине это делает
# .zprofile login-шелла, на свежей — некому
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# trust.json нужен brew bundle ВНУТРИ darwin-rebuild, а homebrew-шаг активации
# идёт ДО home-manager (postActivation) — на первом прогоне pre-seed'им сами;
# следующий switch уводит эти симлинки в *.hm-backup и ставит свои
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

# сделать сортировку по типу параметром по умолчанию на рабочем столе и в папках
