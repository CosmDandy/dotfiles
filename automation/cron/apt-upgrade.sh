#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[apt-upgrade]"

echo "$LOG_PREFIX Updating package lists..."
sudo apt-get update -qq

echo "$LOG_PREFIX Upgrading packages..."
sudo apt-get upgrade -y -qq

echo "$LOG_PREFIX Removing unused packages..."
sudo apt-get autoremove -y -qq

echo "$LOG_PREFIX Rebooting in 1 minute..."
sudo shutdown -r +1
