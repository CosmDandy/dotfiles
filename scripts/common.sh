#!/usr/bin/env zsh

RED='\033[0;31m'
NC='\033[0m'

print_section() {
  local message="$*"
  printf '%0.s~' {1..70}; echo
  echo -e "${RED}$message${NC}"
  printf '%0.s~' {1..70}; echo
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
    IFS=':' read -r source target <<<"$item"
    sudo rm -rf "$target"
    sudo ln -s "$source" "$target"
    echo "Created symlink for $source"
  done
}
