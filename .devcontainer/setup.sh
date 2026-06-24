#!/usr/bin/env bash
set -e

# Locale
echo 'en_US.UTF-8 UTF-8' | sudo tee /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Timezone: containers default to UTC — set local zone so tmux clock, date and
# logs show correct time. Override with CONTAINER_TZ at create time if needed.
CONTAINER_TZ="${CONTAINER_TZ:-Europe/Moscow}"
if [[ -f "/usr/share/zoneinfo/$CONTAINER_TZ" ]]; then
  sudo ln -sf "/usr/share/zoneinfo/$CONTAINER_TZ" /etc/localtime
  echo "$CONTAINER_TZ" | sudo tee /etc/timezone >/dev/null
fi

# Default shell
sudo chsh -s /usr/bin/zsh "$USER"

# System updates + python3-venv for Mason (nvim)
sudo apt-get update && sudo apt-get install -y python3-pip python3-venv
