#!/usr/bin/env zsh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Скрипт целиком интерактивен (open url/app, «нажми Enter») — в headless
# каждый open падает с RBS «Launch failed». Запускать руками в GUI-сессии.
if [[ ! -t 0 ]]; then
  print_section "Skipping interactive app setup (no tty) — запусти platform/macos/install-extra.sh вручную"
  exit 0
fi

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

"$DOTFILES_ROOT/platform/macos/install-arc-extension.sh"

setup_app "Cursor" \
    "Login to account" \
    "Keybindings → Vim" \
    "Open Cursor from Terminal → Install"

setup_app "Visual Studio Code" \
    "Cmd + Shift + P → Shell Command: Install 'code' command in PATH"

"$DOTFILES_ROOT/tools/vscode/install_common.sh"

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

# BetterDisplay: восстановление настроек из кода (tools/betterdisplay/BetterDisplay.plist).
# Заменяет ручной чек-лист. Настройки дисплеев привязаны к UUID железа — на свежей
# macOS может понадобиться один раз перелинковать дисплей в app
# (Settings -> transfer settings of a disconnected display to a connected one).
echo "Restoring BetterDisplay settings from repo..."
osascript -e 'quit app "BetterDisplay"' 2>/dev/null || true
sleep 2
defaults import pro.betterdisplay.BetterDisplay "$DOTFILES_ROOT/tools/betterdisplay/BetterDisplay.plist"
open -a BetterDisplay

# Fallback (если import не применил display-специфичное):
#   Mi Monitor -> HiDPI on, Full EDID match, 59.95Hz, 2560x1440 ; Built-in -> 1280x800
#   Groups Work/Home + Layout Protection (Mi Monitor left/right of Built-in) + Brightness sync

print_section "All apps configured!"

# "amneziavpn"
# "openvpn-connect"
# "jordanbaird-ice"
