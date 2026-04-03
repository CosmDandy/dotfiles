#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# ===============================
# Profiles: base | full (default)
#   base — core editor, shell, git
#   full — base + IaC/K8s/container/DevOps tools
#
# Usage: PROFILE=base ./install.sh
#    or: devpod up --dotfiles-script-env PROFILE=base
# ===============================
PROFILE="${PROFILE:-full}"
print_section "Profile: ${PROFILE}"

# Установка Nix
if ! command -v nix &> /dev/null; then
  print_section "Installing Nix"
  curl -L https://nixos.org/nix/install | sh
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Разрешаем unfree пакеты (например, claude-code)
export NIXPKGS_ALLOW_UNFREE=1

# --- Base: core editing and shell environment ---
packages=(
  # Neovim deps
  python3
  nodejs
  lua
  luarocks
  # CLI
  eza
  fd
  ripgrep
  yq-go
  starship
  neovim
  tmux
  claude-code
  atuin
  btop
  lazygit
  gitleaks
  yamllint
  shellcheck
)

# --- Full: IaC, K8s, DevOps tools ---
if [[ "$PROFILE" == "full" ]]; then
  packages+=(
    go
    uv
    gh
    glab
    gdu
    terraform
    ansible
    kubectl
    kubernetes-helm
    k9s
    dive
    lazydocker
    lnav
    iperf3
  )
fi

nix_args=()
for package in "${packages[@]}"; do
  nix_args+=("nixpkgs.$package")
done
print_section "Installing packages: ${packages[*]}"
nix-env -iA "${nix_args[@]}"

# Создаем символьные ссылки
export XDG_CONFIG_HOME="$HOME/.config"

dirs=(
  "$XDG_CONFIG_HOME"
  "$XDG_CONFIG_HOME/atuin"
  "$XDG_CONFIG_HOME/btop"
  "$XDG_CONFIG_HOME/lazygit"
  "$HOME/.zsh/completions"
  "$HOME/.claude"
  "$HOME/.lnav/configs/default"
)

links=(
  "$DOTFILES_ROOT/tools/tmux/.tmux.conf:$HOME/.tmux.conf"
  "$DOTFILES_ROOT/tools/zsh/.zprofile:$HOME/.zprofile"
  "$DOTFILES_ROOT/tools/zsh/.zshrc:$HOME/.zshrc"
  "$DOTFILES_ROOT/tools/zsh/completions:$HOME/.zsh/completions"
  "$DOTFILES_ROOT/tools/git/.gitignore_global:$HOME/.gitignore_global"
  "$DOTFILES_ROOT/tools/git/.gitconfig:$HOME/.gitconfig"
  "$DOTFILES_ROOT/tools/lazygit/config.yml:$XDG_CONFIG_HOME/lazygit/config.yml"
  "$DOTFILES_ROOT/tools/starship/starship.toml:$XDG_CONFIG_HOME/starship.toml"
  "$DOTFILES_ROOT/tools/atuin/config.toml:$XDG_CONFIG_HOME/atuin/config.toml"
  "$DOTFILES_ROOT/tools/nvim:$XDG_CONFIG_HOME/nvim"
  "$DOTFILES_ROOT/tools/btop/btop.conf:$XDG_CONFIG_HOME/btop/btop.conf"
  "$DOTFILES_ROOT/tools/claude/CLAUDE.md:$HOME/.claude/CLAUDE.md"
  "$DOTFILES_ROOT/tools/claude/settings.json:$HOME/.claude/settings.json"
  "$DOTFILES_ROOT/tools/claude/statusline.sh:$HOME/.claude/statusline.sh"
  "$DOTFILES_ROOT/tools/claude/agents:$HOME/.claude/agents"
  "$DOTFILES_ROOT/tools/claude/commands:$HOME/.claude/commands"
  "$DOTFILES_ROOT/tools/claude/skills:$HOME/.claude/skills"
  "$DOTFILES_ROOT/tools/claude/rules:$HOME/.claude/rules"
  "$DOTFILES_ROOT/tools/lnav/config.json:$HOME/.lnav/configs/default/config.json"
  "$DOTFILES_ROOT/tools/git/.gitconfig-work:$HOME/.gitconfig-work"
  "$DOTFILES_ROOT/tools/git/.allowed_signers:$HOME/.allowed_signers"
  "$DOTFILES_ROOT/tools/git/hooks:$HOME/.git-hooks"
)

print_section "Create directories for symbolic links"
create_directories "${dirs[@]}"

print_section "Create symbolic links"
create_symlinks "${links[@]}"

print_section "Installing tmux plugins"
mkdir -p ~/.tmux/plugins
if [[ ! -d ~/.tmux/plugins/tpm ]]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

print_section "Installing nvim plugins"
nvim --headless "+Lazy! sync" +qa

# TODO: Разобраться с автоматической установкой Mason tools
# Проблема: команда зависает или не находит нужные команды в headless режиме
# Временное решение: установить вручную через :MasonToolsInstall после первого запуска nvim
# print_section "Installing Mason tools (LSP, linters, formatters)"
# nvim --headless "+lua require('mason-tool-installer').check_install(true)" +qa

print_section "Initializing claude submodule"
git -C "$DOTFILES_ROOT" submodule update --init tools/claude/custom

print_section "Installing Claude Code MCP servers"
"$DOTFILES_ROOT/tools/claude/custom/install.sh"

print_section "Setup global gitignore"
git config --global core.excludesfile ~/.gitignore_global

print_section "Installing zinit"
if [[ ! -d "$HOME/.local/share/zinit" ]]; then
  bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
fi

# Плагины zinit будут установлены автоматически при первом запуске zsh

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"
