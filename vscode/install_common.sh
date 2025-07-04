#!/bin/bash
# Универсальный скрипт для установки расширений в VS Code и Cursor

install_extensions() {
  local cmd="$1"
  shift
  local exts=("$@")

  for ext in "${exts[@]}"; do
    echo "Installing extension '$ext'..."
    # Используем --force для обновления уже установленных расширений
    if $cmd --install-extension "$ext" --force; then
      echo "✓ Successfully installed/updated $ext"
    else
      echo "✗ Failed to install $ext"
    fi
  done
}

# Проверяем доступность команд
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" &> /dev/null; then
    echo "Warning: $cmd is not available"
    return 1
  fi
  return 0
}

# Общие расширения для обоих редакторов
COMMON_EXTENSIONS=(
  vscodevim.vim
  ms-python.python
  ms-toolsai.jupyter
  charliermarsh.ruff
  ms-python.black-formatter
  ms-python.mypy-type-checker
  ms-python.isort
  trinhanhngoc.vscode-odoo
  eamodio.gitlens
  wakatime.vscode-wakatime
  pkief.material-icon-theme
)

# Специфичные для VS Code
VSCODE_SPECIFIC_EXTENSIONS=(
  ms-vsliveshare.vsliveshare
  ms-vscode-remote.remote-ssh
  ms-vscode-remote.remote-containers
  ms-vscode.remote-explorer
)

# Специфичные для Cursor
CURSOR_SPECIFIC_EXTENSIONS=(
  anysphere.remote-containers
  anysphere.remote-ssh
  anysphere.cursorpyright
)

echo "=== Installing VS Code Extensions ==="
if check_command code; then
  # Складываем списки и устанавливаем для VS Code
  ALL_VSCODE_EXTENSIONS=("${COMMON_EXTENSIONS[@]}" "${VSCODE_SPECIFIC_EXTENSIONS[@]}")
  install_extensions code "${ALL_VSCODE_EXTENSIONS[@]}"
else
  echo "VS Code CLI not available, skipping VS Code extensions"
fi

echo ""
echo "=== Installing Cursor Extensions ==="
if check_command cursor; then
  # Складываем списки и устанавливаем для Cursor
  ALL_CURSOR_EXTENSIONS=("${COMMON_EXTENSIONS[@]}" "${CURSOR_SPECIFIC_EXTENSIONS[@]}")
  install_extensions cursor "${ALL_CURSOR_EXTENSIONS[@]}"
else
  echo "Cursor CLI not available, skipping Cursor extensions"
fi

echo ""
echo "=== Installation Summary ==="
echo "Installation completed. Check the output above for any failed extensions."
