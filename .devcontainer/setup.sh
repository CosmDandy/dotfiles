#!/usr/bin/env bash
set -e

# Everything below is already done while building the prebuilt image, which leaves a
# marker. Repeating it on every workspace creation is an apt-get update over the network
# plus reinstalling what is already there. Bare mcr.microsoft.com/devcontainers/base images
# (the other repositories) have no marker and run the whole script.
if [[ -f /etc/devcontainer-prebuilt ]]; then
  echo "prebuilt image ($(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo '?')) — system prep baked in, skipping"
  # NOTE: .zcompdump is baked into the image, so its mtime is the BUILD time rather than
  # the workspace creation time. The guard in .zshrc treats a dump older than a day as
  # stale and runs a full compinit with compaudit — ~450 ms on the first start of EVERY new
  # workspace, while the contents are perfectly valid. Only the date needs refreshing.
  # NOTE: not `[[ … ]] && touch` — under `set -e` a missing file would make the last
  # command return 1 and kill the whole script.
  if [[ -f "$HOME/.zcompdump" ]]; then
    touch "$HOME/.zcompdump"
  fi
  exit 0
fi

# Locale
echo 'en_US.UTF-8 UTF-8' | sudo tee /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Containers default to UTC; override with CONTAINER_TZ at create time.
CONTAINER_TZ="${CONTAINER_TZ:-Europe/Moscow}"
if [[ -f "/usr/share/zoneinfo/$CONTAINER_TZ" ]]; then
  sudo ln -sf "/usr/share/zoneinfo/$CONTAINER_TZ" /etc/localtime
  echo "$CONTAINER_TZ" | sudo tee /etc/timezone >/dev/null
fi

# Default shell
sudo chsh -s /usr/bin/zsh "$USER"

# System updates plus python3-venv for Mason (nvim)
sudo apt-get update && sudo apt-get install -y python3-pip python3-venv
