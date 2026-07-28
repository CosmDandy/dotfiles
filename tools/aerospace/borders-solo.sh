#!/usr/bin/env bash
# Гасит рамку активного окна, когда на воркспейсе оно одно: подсвечивать
# нечего, выбирать не из чего. Своего условия «сколько окон» у JankyBorders
# нет, поэтому логика живёт здесь, а зовут её колбэки aerospace.
set -u

AEROSPACE=/opt/homebrew/bin/aerospace
BORDERS=/run/current-system/sw/bin/borders
PLIST="$HOME/Library/LaunchAgents/org.nixos.jankyborders.plist"
STATE="${TMPDIR:-/tmp}/borders-solo.state"

[ -x "$BORDERS" ] || exit 0

# Цвет не дублируем: берём тот, что nix положил в plist агента. Иначе он
# разъедется с darwin-configuration.nix при первой же правке.
COLOR=$(sed -n 's|.*<string>active_color=\(0x[0-9a-fA-F]*\)</string>.*|\1|p' "$PLIST" 2>/dev/null | head -1)
COLOR=${COLOR:-0xff248d83}

count=$("$AEROSPACE" list-windows --workspace focused --count 2>/dev/null) || exit 0

if [ "${count:-0}" -le 1 ]; then want=hidden; else want=shown; fi

# Колбэк прилетает на каждое переключение фокуса — при навигации это
# несколько раз в секунду. Дёргаем borders только когда состояние сменилось.
[ "$(cat "$STATE" 2>/dev/null)" = "$want" ] && exit 0
printf '%s' "$want" >"$STATE"

if [ "$want" = hidden ]; then
  "$BORDERS" active_color=0x00000000
else
  "$BORDERS" active_color="$COLOR"
fi
