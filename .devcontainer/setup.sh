#!/usr/bin/env bash
set -e

# Всё ниже уже выполнено на этапе сборки пребилт-образа (platform/linux/
# Dockerfile ставит маркер). Повтор на каждом создании воркспейса — это
# лишний apt-get update по сети и переустановка того, что уже стоит.
# Голые образы mcr.microsoft.com/devcontainers/base (остальные репозитории)
# маркера не имеют и проходят скрипт целиком.
if [[ -f /etc/devcontainer-prebuilt ]]; then
  echo "prebuilt image ($(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo '?')) — system prep baked in, skipping"
  # .zcompdump запечён в образ при сборке, поэтому его mtime — это время СБОРКИ
  # образа, а не создания воркспейса. Гард в .zshrc (`(#qN.mh+24)`) считает дамп
  # старше суток протухшим и уходит в полный compinit с compaudit — ~450 мс на
  # первом старте КАЖДОГО нового воркспейса, при том что содержимое дампа
  # валидно: пакеты те же, что при сборке. Освежаем только дату.
  # Не `[[ … ]] && touch`: под `set -e` отсутствие файла дало бы код 1 на
  # последней команде и уронило скрипт целиком.
  if [[ -f "$HOME/.zcompdump" ]]; then
    touch "$HOME/.zcompdump"
  fi
  exit 0
fi

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
