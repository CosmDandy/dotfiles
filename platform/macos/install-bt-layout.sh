#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${DOTFILES}/automation/launchd/scripts/bt-layout-switch.app"
SCRIPT="${APP}/Contents/MacOS/bt-layout-switch"
CONFIG="${DOTFILES}/automation/launchd/config/bt-layout.conf"
PLIST_SRC="${DOTFILES}/automation/launchd/agents/com.cosmdandy.bt-layout-switch.plist"
PLIST_DST="${HOME}/Library/LaunchAgents/com.cosmdandy.bt-layout-switch.plist"
LABEL="com.cosmdandy.bt-layout-switch"

# Ensure app bundle structure exists
mkdir -p "${APP}/Contents/MacOS"

# Recompile binary if source is newer
SRC="${DOTFILES}/automation/launchd/scripts/bt-layout-switch.swift"
if [[ ! -f "$SCRIPT" || "$SRC" -nt "$SCRIPT" ]]; then
    echo "Compiling bt-layout-switch..."
    swiftc "$SRC" -framework IOBluetooth -framework Carbon -framework AppKit -o "$SCRIPT"
    echo "  done"
    # Sign the bundle so TCC tracks by CFBundleIdentifier (stable across recompiles)
    codesign --force --sign - "$APP"
    echo "  signed (bundle ID: com.cosmdandy.bt-layout-switch)"
fi

# Check KEYBOARD_MAC is set
MAC=$(grep '^KEYBOARD_MAC=' "$CONFIG" | cut -d= -f2 | tr -d '" ')
if [[ -z "$MAC" ]]; then
    echo ""
    echo "Step 1: Grant Bluetooth permission (first time only)"
    echo "  Run from Ghostty to trigger macOS permission dialog:"
    echo "    $SCRIPT --list-devices"
    echo "  Approve the Bluetooth access request."
    echo ""
    echo "Step 2: Fill in KEYBOARD_MAC in:"
    echo "  $CONFIG"
    echo ""
    echo "  Get MAC from: System Settings → Bluetooth (hover keyboard)"
    echo "  Or from the output of Step 1 above."
    echo ""
    echo "Step 3: Re-run this script."
    exit 1
fi

# Symlink plist
ln -sf "$PLIST_SRC" "$PLIST_DST"

# Load agent (unload first if already running)
launchctl bootout "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

echo "bt-layout-switch installed and started"
echo "  config : $CONFIG"
echo "  log    : /tmp/bt-layout-switch.log"
echo "  status : launchctl list | grep bt-layout"
echo ""
echo "One-time permissions (approve each, then restart daemon):"
echo ""
echo "  1. Bluetooth — approve the dialog that macOS shows automatically."
echo "     (Or run: $SCRIPT --list-devices)"
echo ""
echo "  2. Keyboard layout — run from Ghostty:"
echo "       $SCRIPT --request-layout-permission"
echo "     Approve the 'allow enabling keyboard layout' dialog."
echo ""
echo "  3. Accessibility — run from Ghostty:"
echo "       $SCRIPT --request-accessibility"
echo "     Approve in System Settings → Privacy & Security → Accessibility."
echo ""
echo "After all three are approved, restart:"
echo "  launchctl kickstart -k \"gui/\$(id -u)/com.cosmdandy.bt-layout-switch\""
