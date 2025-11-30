#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

print_section "Installing apps"
links=(
    "https://appstorrent.ru/48-final-cut-pro.html"
    "https://appstorrent.ru/87-capture-one.html"
    "https://appstorrent.ru/1938-istatistica-pro.html"
    "https://appstorrent.ru/1789-network-radar.html"
    "https://appstorrent.ru/423-kaleidoscope.html"
    "https://appstorrent.ru/3019-screen-studio.html"
    "https://appstorrent.ru/162-transmit.html"
    "https://appstorrent.ru/672-cleanshot-x.html"
    "https://appstorrent.ru/3647-superwhisper.html"
    "https://appstorrent.ru/42-things-3.html"
    "https://www.logitech.com/en-eu/software/logi-options-plus.html"
)

for link in "${links[@]}"; do
    echo "Opening link: $link"
    open "$link"
    sleep 1
done

confirm "Press 'y' when download all files"

setup_app "OrbStack" \
    "Start at login → on" \
    "Automatically download updates → on" \
    "Memory limit → max" \
    "CPU → max-1" \
    "Hide OrbStack volume from Finder & Desktop → on"

setup_app "Leader Key" \
    "Shortcut → F10" \
    "Theme → Breadcrumbs" \
    "Launch at login → on" \
    "Activation → Reset group selection" \
    "Show Leader Key in menubar → off" \
    "Force English keyboard layout → on"

setup_app "logioptionsplus" \
    "Add MX Master via Bluetooth" \
    "ВОССТАНОВИТЬ НАСТРОЙКИ ИЗ РЕЗЕРВНОЙ КОПИИ"

setup_app "Things3" \
    "Счетчик на наклейке в Dock → Сегодня + Входящие" \
    "Группировать задачи в «Сегодня» по проектам → on" \
    "Things Cloud → Sync" \
    "Быстрый ввод: Command + F2" \
    "Быстрый ввод с: Command + F3" \
    "Показывать события из календаря в списках задач «Сегодня» и «Планы» → on"

setup_app "SuperWhisper" \
    "Create mode → Voice to text → Voice Model → Ultra V3 Turbo" \
    "Toggle Recording → Command + F1" \
    "Automatically check for updates → off" \
    "Launch on login → on" \
    "Mini Recording window → on" \
    "Always show Mini Recording Window → off" \
    "Show in Dock → off" \
    "Dynamic normalization → on"

setup_app "CleanShot X" \
    "Startup: Start at login → on" \
    "Menu bar: Show icon → off" \
    "Desktop icons: Hide while capturing → on" \
    "Copy file to clipboard: Screenshot → on" \
    "Auto-close: Enable → on" \
    "Retina: Scale Retina videos to 1x → on" \
    "Notifications: Do Not Disturb while recording → on" \
    "Recording area: Dim screen while recording → off" \
    "Max resolution: 1080p" \
    "Video FPS: 25" \
    "Freeze screen: Freeze screen when taking a screenshot → on" \
    "Automatically check for updates → off"

setup_app "Activation Tool" \
    "激活/Activation" \
    "确定 (Принять)" \
    "退出/Exit (Выход)" \
    "Highlight recorded area during recording → off"
sudo rm -rf "/Applications/Activation Tool.app"

setup_app "Raycast" \
    "Import Data"

setup_app "Obsidian" \
    "Add my Knowledge Base"

setup_app "AeroSpace" \
    "Experimental Ul Settings  → on"

setup_app "Timing" \
    "Login to account"

setup_app "Arc" \
    "Login to account"

$SCRIPT_DIR/scripts/macos/install_arc_extension.sh

setup_app "Cursor" \
    "Login to account" \
    "Keybindings → Vim" \
    "Open Cursor from Terminal → Install"

setup_app "Visual Studio Code" \
    "Cmd + Shift + P → Shell Command: Install 'code' command in PATH"

$SCRIPT_DIR/vscode/install_common.sh

setup_app "ChatGPT" \
    "Login to account"

setup_app "Claude" \
    "Login to account"

setup_app "Telegram" \
    "Login to My account" \
    "Login to Work account"

setup_app "WhatsApp" \
    "Login to account"

setup_app "Microsoft Teams" \
    "Login to account"

setup_app "iStatistica Pro" \
    "Download iStatistica Sensors Plugin"

setup_app "Transmit"

setup_app "UTM"

setup_app "Onyx"

setup_app "Ukelele"

setup_app "Kaleidoscope"

setup_app "Network Radar"

setup_app "Final Cut Pro"

setup_app "Capture One"

setup_app "DevPod"

setup_app "Karabiner-Elements" \
    "Disable the built-in keyboard while this device is connected → on"

setup_app "Flux" \
    "Pick location"

setup_app "BetterDisplay" \
    "Mi Monitor → Edit the system configuration of this display model → on" \
    "Mi Monitor → General Settings → Additional settings... → Display identification method → Full EDID match" \
    "Mi Monitor → Refresh Rate → 59.95Hz" \
    "Mi Monitor → High Resolution (HiDPI) → on" \
    "Mi Monitor → Resolution → 2560x1440" \
    "Built-in Display → Resolution → 1280x800" \
    "Create Work & Home group" \
    "Work/Home Group → Group Membership → Exclude some displays from the group → Mi Monitor" \
    "Work/Home Group → Synchronization Settings → Add New Synchronization... → Brightness → Synchronize changes triggered externally → on" \
    "Home Group → Layout Protection → Enable layout protection → Add New Protection... → Mi Monitor → Arrange Mi Monitor next to: Built-in Display → Position of Mi Monitor: Right of Built-in Display → Adjust anchor point offsets → on" \
    "Work Group → Layout Protection → Enable layout protection → Add New Protection... → Mi Monitor → Arrange Mi Monitor next to: Built-in Display → Position of Mi Monitor: Left of Built-in Display → Adjust anchor point offsets → on"

print_section "All apps configured!"

# "amneziavpn"
# "openvpn-connect"
# "jordanbaird-ice"
