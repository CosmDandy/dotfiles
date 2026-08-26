#!/usr/bin/env bash
# Weekly host package upgrade, installed into crontab by automation/cron/install.sh.
#
# NOTE: requires NOPASSWD sudo — there is nobody to type a password from cron, and without
# the rule the script hangs silently until the timeout. The line in
# /etc/sudoers.d/apt-upgrade lists the commands by name rather than granting NOPASSWD: ALL:
#   <user> ALL=(root) NOPASSWD: /usr/bin/apt-get, /usr/sbin/shutdown
set -euo pipefail

LOG_PREFIX="[apt-upgrade]"

echo "$LOG_PREFIX Updating package lists..."
sudo apt-get update -qq

echo "$LOG_PREFIX Upgrading packages..."
sudo apt-get upgrade -y -qq

echo "$LOG_PREFIX Removing unused packages..."
sudo apt-get autoremove -y -qq

# NOTE: reboot only when the package manager asks for it. It used to be unconditional, so
# the server rebooted every Sunday even for man-page updates, taking every running devpod
# container with it. /var/run/reboot-required is created by the postinst scripts of the
# kernel, libc, dbus and systemd — exactly the cases where the update needs one.
if [[ -f /var/run/reboot-required ]]; then
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo "$LOG_PREFIX Reboot required by: $(tr '\n' ' ' < /var/run/reboot-required.pkgs)"
  fi
  echo "$LOG_PREFIX Rebooting in 1 minute..."
  sudo shutdown -r +1
else
  echo "$LOG_PREFIX Reboot not required"
fi
