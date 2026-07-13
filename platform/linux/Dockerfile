# Prebuilt devcontainer-образ для DevPod: Ubuntu + Nix + home-manager full-профиль.
# Собирается в CI (.github/workflows/devcontainer-image.yml) под amd64+arm64,
# публикуется как ghcr.io/cosmdandy/devcontainer:full. Store-пути совпадают с
# flake.lock репо, поэтому home-manager switch при devpod up — мгновенный no-op.
# ubuntu-24.04 (пин по digest мульти-арх индекса)
FROM mcr.microsoft.com/devcontainers/base@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae

ARG PROFILE=full
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
  && mkdir -m 0755 /nix && chown vscode:vscode /nix

USER vscode
ENV USER=vscode \
    HOME=/home/vscode
WORKDIR /home/vscode

# Nix single-user (версия запинена)
RUN curl -fsSL https://releases.nixos.org/nix/nix-2.33.1/install | sh -s -- --no-daemon \
  && mkdir -p "$HOME/.config/nix" \
  && echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"

ENV PATH=/home/vscode/.nix-profile/bin:$PATH

# home-manager профиль запекается в образ; gc в том же слое выкидывает
# build-зависимости (Go-тулчейн terraform и т.п.) из итогового размера
COPY --chown=vscode:vscode platform/nix /opt/dotfiles/platform/nix
RUN nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#vscode-${PROFILE}-$(uname -m)-linux" -b hm-backup \
  && nix-collect-garbage -d
