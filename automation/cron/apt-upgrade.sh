#!/usr/bin/env bash
# Еженедельное обновление пакетов хоста. Ставится в crontab через
# automation/cron/install.sh.
#
# ТРЕБУЕТ NOPASSWD-sudo: из cron некому ввести пароль, и без этого правила
# скрипт молча висит до таймаута. Нужная строка в /etc/sudoers.d/apt-upgrade:
#   <user> ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/sbin/shutdown
# Перечислять команды поимённо, а не давать NOPASSWD: ALL.
set -euo pipefail

LOG_PREFIX="[apt-upgrade]"

echo "$LOG_PREFIX Updating package lists..."
sudo apt-get update -qq

echo "$LOG_PREFIX Upgrading packages..."
sudo apt-get upgrade -y -qq

echo "$LOG_PREFIX Removing unused packages..."
sudo apt-get autoremove -y -qq

# Перезагрузка — только когда её требует сам пакетный менеджер. Раньше ребут
# был безусловным: сервер уходил в перезагрузку каждое воскресенье, даже если
# обновились одни только man-страницы, и вместе с ним падали все запущенные
# devpod-контейнеры. /var/run/reboot-required создают postinst-скрипты ядра,
# libc, dbus и systemd — то есть ровно те случаи, когда без ребута обновление
# не вступит в силу.
if [[ -f /var/run/reboot-required ]]; then
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo "$LOG_PREFIX Reboot required by: $(tr '\n' ' ' < /var/run/reboot-required.pkgs)"
  fi
  echo "$LOG_PREFIX Rebooting in 1 minute..."
  sudo shutdown -r +1
else
  echo "$LOG_PREFIX Reboot not required"
fi
