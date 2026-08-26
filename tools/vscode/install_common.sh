#!/bin/bash
# Installs the extension sets into VS Code and Cursor.

install_extensions() {
  local cmd="$1"
  shift
  local exts=("$@")

  for ext in "${exts[@]}"; do
    echo "Installing extension '$ext'..."
    # --force so already installed extensions are updated
    if $cmd --install-extension "$ext" --force; then
      echo "✓ Successfully installed/updated $ext"
    else
      echo "✗ Failed to install $ext"
    fi
  done
}

# check which editors are available
check_command() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    echo "Warning: $cmd is not available"
    return 1
  fi
  return 0
}

# shared by both editors
COMMON_EXTENSIONS=(
  vscodevim.vim
  ms-python.python
  ms-toolsai.jupyter
  charliermarsh.ruff
  ms-python.black-formatter
  ms-python.mypy-type-checker
  ms-python.isort
  eamodio.gitlens
  wakatime.vscode-wakatime
  pkief.material-icon-theme
)

# VS Code only
VSCODE_SPECIFIC_EXTENSIONS=(
  ms-vsliveshare.vsliveshare
  ms-vscode-remote.remote-ssh
  ms-vscode-remote.remote-containers
  ms-vscode.remote-explorer
)

# Cursor only
CURSOR_SPECIFIC_EXTENSIONS=(
  anysphere.remote-containers
  anysphere.remote-ssh
  anysphere.cursorpyright
)

echo "=== Installing VS Code Extensions ==="
if check_command code; then
  # combine the lists for VS Code
  ALL_VSCODE_EXTENSIONS=("${COMMON_EXTENSIONS[@]}" "${VSCODE_SPECIFIC_EXTENSIONS[@]}")
  install_extensions code "${ALL_VSCODE_EXTENSIONS[@]}"
else
  echo "VS Code CLI not available, skipping VS Code extensions"
fi

echo ""
echo "=== Installing Cursor Extensions ==="
if check_command cursor; then
  # combine the lists for Cursor
  ALL_CURSOR_EXTENSIONS=("${COMMON_EXTENSIONS[@]}" "${CURSOR_SPECIFIC_EXTENSIONS[@]}")
  install_extensions cursor "${ALL_CURSOR_EXTENSIONS[@]}"
else
  echo "Cursor CLI not available, skipping Cursor extensions"
fi

echo ""
echo "=== Installation Summary ==="
echo "Installation completed. Check the output above for any failed extensions."
