{ pkgs, ... }:

with pkgs; [
  # Языки программирования
  nodejs
  python3
  go
  uv
  lua
  luarocks
  rustc
  cargo

  # CLI утилиты
  eza
  fd
  ripgrep
  iperf3
  unzip
  wget
  curl
  jq
  ansible
  terraform

  # Разработка
  starship
  neovim
  tmux
  atuin
  btop

  # Git инструменты
  git
  gh        # GitHub CLI
  glab      # GitLab CLI
  lazygit
  lazydocker
  dive
  k9s
]
