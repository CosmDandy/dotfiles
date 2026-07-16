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

# Источники дистрибутивов — в приватном сабмодуле: репозиторий публичный.
# Sourced, а не запуск отдельным процессом: скрипту нужны print_section,
# confirm и setup_app, объявленные в common.sh выше. Файл только ОБЪЯВЛЯЕТ
# функции; вызываются они ниже, каждая на своём месте.
EXTRA_SOURCES="$DOTFILES_ROOT/private/macos/extra-apps.sh"
if [[ -f "$EXTRA_SOURCES" ]]; then
    source "$EXTRA_SOURCES"
    extra_download_sources
else
    print_section "private/macos/extra-apps.sh не найден (сабмодуль не инициализирован) — источники пропущены"
fi

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

# Активация — здесь же, где стояла раньше: приложения, которые тул патчит, к
# этому моменту установлены и настроены.
if typeset -f extra_activation >/dev/null; then
    extra_activation
fi

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

setup_app "Visual Studio Code" \
    "Cmd + Shift + P → Shell Command: Install 'code' command in PATH"

"$DOTFILES_ROOT/tools/vscode/install_common.sh"

setup_app "Claude" \
    "Login to account"

setup_app "Telegram" \
    "Login to My account" \
    "Login to Work account"

setup_app "Microsoft Teams" \
    "Login to account"

setup_app "UTM"

setup_app "Onyx"

setup_app "Final Cut Pro"

setup_app "Capture One"

setup_app "DevPod"

setup_app "Karabiner-Elements" \
    "Disable the built-in keyboard while this device is connected → on"

setup_app "Flux" \
    "Pick location"

# BetterDisplay: plist в репо не держим (EDID, серийники мониторов, маркер
# лицензии — публичный репозиторий). Настройки восстанавливаются из restic-бэкапа:
#   restic restore --target / --include "$HOME/Library/Preferences/pro.betterdisplay.BetterDisplay.plist" latest
# затем перезапустить BetterDisplay. Привязка к дисплеям идёт по UUID железа — на
# свежей macOS может понадобиться перелинковать дисплей
# (Settings -> transfer settings of a disconnected display to a connected one).
setup_app "BetterDisplay" \
    "Restore plist из бэкапа (см. комментарий) ЛИБО вручную:" \
    "Mi Monitor -> HiDPI on, Full EDID match, 59.95Hz, 2560x1440" \
    "Built-in -> 1280x800" \
    "Groups Work/Home + Layout Protection + Brightness sync"

print_section "All apps configured!"

# "amneziavpn"
# "openvpn-connect"
# "jordanbaird-ice"
