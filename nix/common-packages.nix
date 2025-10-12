{ pkgs, ... }:

with pkgs; [
  # Основные CLI утилиты
  starship
  eza
  tmux
  btop

  # Git инструменты
  git
  lazygit
  lazydocker

  # Языки программирования
  nodejs
  python3
  uv
  lua
  luarocks
  rustc
  cargo
  go

  # Поиск и навигация
  fd
  ripgrep

  # Редакторы
  neovim

  # История команд
  atuin

  # Сетевые утилиты
  iperf3
  speedtest-cli

  # Системные утилиты
  wget
  curl
  unzip
]
