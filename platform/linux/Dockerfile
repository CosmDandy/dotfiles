# Prebuilt devcontainer-образ для DevPod: Ubuntu + Nix + home-manager.
# Собирается в CI (.github/workflows/devcontainer-image.yml) под amd64+arm64,
# публикуется как ghcr.io/cosmdandy/devcontainer:{core,devops}. Store-пути
# совпадают с flake.lock репо, поэтому home-manager switch при devpod up —
# мгновенный no-op.
#
# Профиль выбирается стадией, а не build-arg: `--target core` / `--target devops`.
# Смысл в том, что devops наследует стадию core, поэтому нижние слои у двух
# образов буквально одни и те же — реестр их дедуплицирует, а имея :core,
# клиент дотягивает :devops одной дельтой. Заодно монолитный слой на ~1.2 ГБ
# разбивается надвое, что даёт параллельную загрузку.
#
# ВАЖНО: nix-collect-garbage обязан оставаться в ТОМ ЖЕ RUN, что и switch.
# Удаление отдельным слоем не освобождает место — файлы остаются в нижнем слое
# под whiteout'ом (проверено: 68 MiB против 8 MiB на синтетике), и build-
# зависимости вроде Go-тулчейна terraform запеклись бы в образ навсегда.

# ubuntu-24.04 (пин по digest мульти-арх индекса)
FROM mcr.microsoft.com/devcontainers/base@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae AS base

ENV TZ=Europe/Moscow \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Системная часть — то же, что .devcontainer/setup.sh делает на голом образе
RUN apt-get update \
  && apt-get install -y --no-install-recommends zsh python3-pip python3-venv locales \
  && rm -rf /var/lib/apt/lists/* \
  && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  && ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime \
  && echo "$TZ" > /etc/timezone \
  && chsh -s /usr/bin/zsh vscode \
  && mkdir -m 0755 /nix && chown vscode:vscode /nix \
  # маркер для .devcontainer/setup.sh: системная подготовка уже в образе,
  # повторять её при каждом создании воркспейса незачем
  && echo prebuilt > /etc/devcontainer-prebuilt

USER vscode
ENV USER=vscode \
    HOME=/home/vscode
WORKDIR /home/vscode

# Nix single-user: версия запинена, скрипт сверяется с checksum (security.md);
# --no-channel-add — канал не нужен (всё флейковое) и иначе запёк бы ~400MB
# незапиненного nixpkgs-unstable в образ мимо nix-collect-garbage
RUN curl -fsSL https://releases.nixos.org/nix/nix-2.33.1/install -o /tmp/nix-install \
  && echo "2bbe0d388d1bee5ee60ed67b844f428b6031a1b7c42d7d03319ad7133867290d  /tmp/nix-install" | sha256sum -c - \
  && sh /tmp/nix-install --no-daemon --no-channel-add \
  && rm /tmp/nix-install \
  && mkdir -p "$HOME/.config/nix" \
  && echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"

ENV PATH=/home/vscode/.nix-profile/bin:$PATH

COPY --chown=vscode:vscode platform/nix /opt/dotfiles/platform/nix

# Конфиг nvim нужен хукам: home-manager линкует ~/.config/nvim ->
# ~/dotfiles/tools/nvim (mkOutOfStoreSymlink), и без него симлинк висячий,
# guard `-e ~/.config/nvim/init.lua` не проходит, а syncNvimPlugins/
# installMasonTools молча пропускаются — плагины и mason качались в КАЖДЫЙ
# воркспейс (1.2 ГБ).
#
# Лежит в /opt, а НЕ в ~/dotfiles: туда devpod клонирует настоящий репозиторий,
# непустой каталог сломал бы клон. На время активации каждая стадия вешает
# симлинк ~/dotfiles -> /opt/dotfiles и снимает его в том же RUN — снятие
# мгновенное и следа в слое не оставляет.
#
# Симлинк обязан создаваться в КАЖДОЙ стадии: devops собирается поверх core, и
# пока core сносил каталог насовсем, devops оставался с висячим симлинком и
# пропускал mason — из-за чего jsonnet-language-server (ему нужен go, а он
# только в devops-профиле) не попадал в образ вообще никогда.
COPY --chown=vscode:vscode tools/nvim /opt/dotfiles/tools/nvim

# --- core: редактор, шелл, git, CI ---
# ~/.dotfiles-profile — тот же файл, что пишет platform/linux/install.sh и
# читают updl с devpod-update.sh: запечённый в образ, он даёт рабочий updl
# сразу, ещё до первого запуска install.sh
FROM base AS core
RUN ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#vscode-core-$(uname -m)-linux" -b hm-backup \
  && rm -f "$HOME/dotfiles" \
  # кэши сборки mason (npm ~71 МБ, go ~66 МБ) — мусор, сами пакеты уже в
  # ~/.local/share/nvim/mason; в том же RUN, иначе останутся под whiteout
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
  && nix-collect-garbage -d \
  && echo core > "$HOME/.dotfiles-profile"

# --- devops: core + IaC/K8s/container ---
# Наследует core целиком, поэтому в слой ложится только дельта пакетов
FROM core AS devops
RUN ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#vscode-devops-$(uname -m)-linux" -b hm-backup \
  && rm -f "$HOME/dotfiles" \
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
  && nix-collect-garbage -d \
  && echo devops > "$HOME/.dotfiles-profile"
