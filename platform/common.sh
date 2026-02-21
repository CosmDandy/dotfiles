#!/usr/bin/env zsh

# Если DOTFILES_ROOT не определена (скрипт запущен напрямую, а не через setup.sh)
if [ -z "$DOTFILES_ROOT" ]; then
  PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export DOTFILES_ROOT="$(dirname "$PLATFORM_DIR")"
fi

RED='\033[0;31m'
NC='\033[0m'

print_section() {
  local message="$*"
  printf '%0.s~' {1..70}
  echo
  echo -e "${RED}$message${NC}"
  printf '%0.s~' {1..70}
  echo
}

confirm() {
  while true; do
    read -k 1 "REPLY?$1 (y/n): "
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Continuing..."
      return 0
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
      echo "Cancelled"
      exit 1
    else
      echo "Please enter y or n"
    fi
  done
}

# Функция для настройки приложения с интерактивным подтверждением
setup_app() {
  local app_name="$1"
  shift
  local tasks=("$@")

  print_section "Setting up: $app_name"
  open -a "$app_name"

  if [[ ${#tasks[@]} -gt 0 ]]; then
    echo "Tasks to complete:"
    for task in "${tasks[@]}"; do
      echo "  • $task"
    done
  fi

  echo ""
  read "response?Press Enter when done (or 's' to skip): "

  if [[ "$response" == "s" ]]; then
    echo "⊘ Skipped $app_name"
  else
    echo "✓ Completed $app_name"
  fi
  echo ""

  osascript -e "quit app \"$app_name\""
}

create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    echo "Created directory ${dir}"
  done
}

create_symlinks() {
  local items=("$@")
  for item in "${items[@]}"; do
    IFS=':' read -r source target <<< "$item"
    sudo rm -rf "$target"
    sudo ln -s "$source" "$target"
    echo "Created symlink for $source"
  done
}
