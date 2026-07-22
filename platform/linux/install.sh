#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# ===============================
# Тонкий bootstrap: всё окружение (пакеты, симлинки, установщики) декларируется
# в platform/nix/home/ и применяется одним home-manager switch. Здесь остаётся
# только неустранимый минимум: nix, flakes, bridge-симлинк и system-уровень.
#
# Profiles: core | devops
# Usage: PROFILE=core ./install.sh
#    or: devpod up --dotfiles-script-env PROFILE=core
#
# Без явной переменной профиль берётся из маркера, который пребилт-образ пишет
# в ~/.dotfiles-profile (platform/linux/Dockerfile). Иначе на :core-образ
# разворачивался бы devops-профиль: home-manager тянул бы terraform, ansible,
# kubectl и k9s в персональный слой контейнера — ровно то, от чего уходили
# (замерено: 5м41с против ~20с). На голом образе без маркера — devops, как было.
# ===============================
PROFILE="${PROFILE:-$(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo devops)}"
print_section "Profile: ${PROFILE}"

# Установка Nix (--no-channel-add: каналы не нужны — пакеты едут по flake.lock,
# а дефолтный nixpkgs-unstable канал тянет ~400MB незапиненного дерева)
if ! command -v nix &> /dev/null; then
  print_section "Installing Nix"
  curl -L https://nixos.org/nix/install | sh -s -- --no-channel-add
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Flakes нужны для home-manager; ванильный nix не включает их по умолчанию
mkdir -p "$HOME/.config/nix"
if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
fi

# Bridge-симлинки: home-модули (files.nix/hooks.nix) ссылаются на ~/dotfiles,
# конфиги исторически — на ~/.dotfiles. Оба пути должны вести в один клон.
# DevPod клонирует в ~/dotfiles (clone-path не настраивается), руками часто ~/.dotfiles
[[ "$DOTFILES_ROOT" != "$HOME/.dotfiles" && ! -e "$HOME/.dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/.dotfiles"
[[ "$DOTFILES_ROOT" != "$HOME/dotfiles" && ! -e "$HOME/dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/dotfiles"

# ===============================
# Весь user-space одним switch: пакеты + симлинки + activation-хуки
# (claude, ccusage, zinit, nvim-плагины, MCP). Версии пиннятся flake.lock.
# Атрибут: <user>-<profile>-<arch>, см. platform/nix/flake.nix
# ===============================
FLAKE_DIR="$DOTFILES_ROOT/platform/nix"
HM_CONFIG="$(whoami)-${PROFILE}-$(uname -m)-linux"

print_section "Activating home-manager configuration: ${HM_CONFIG}"
# --inputs-from: home-manager резолвится по flake.lock репо, а не по свежему master;
# -b: файлы, которые HM отказался бы перезаписать, уезжают в *.hm-backup
nix run --inputs-from "$FLAKE_DIR" home-manager -- switch --flake "$FLAKE_DIR#${HM_CONFIG}" -b hm-backup

# Маркер профиля — читает cron-обновление (automation/cron/devpod-update.sh)
echo "$PROFILE" > "$HOME/.dotfiles-profile"

# ===============================
# System-уровень (sudo): вне зоны home-manager. В prebuilt-образе уже сделано —
# эти шаги идемпотентны и отрабатывают мгновенно
# ===============================
print_section "Setting default shell to zsh"
ZSH_PATH="$(which zsh)"
if [[ "$SHELL" != "$ZSH_PATH" ]]; then
  if grep -q "$ZSH_PATH" /etc/shells 2>/dev/null; then
    chsh -s "$ZSH_PATH" 2>/dev/null || sudo chsh -s "$ZSH_PATH" "$(whoami)" 2>/dev/null || true
  else
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    chsh -s "$ZSH_PATH" 2>/dev/null || sudo chsh -s "$ZSH_PATH" "$(whoami)" 2>/dev/null || true
  fi
fi

# Timezone: containers default to UTC — set local zone so tmux clock, date and
# logs show correct time. Override with CONTAINER_TZ at create time if needed.
CONTAINER_TZ="${CONTAINER_TZ:-Europe/Moscow}"
if [[ -f "/usr/share/zoneinfo/$CONTAINER_TZ" ]]; then
  print_section "Setting timezone to ${CONTAINER_TZ}"
  sudo ln -sf "/usr/share/zoneinfo/$CONTAINER_TZ" /etc/localtime
  echo "$CONTAINER_TZ" | sudo tee /etc/timezone >/dev/null
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"
