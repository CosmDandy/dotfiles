#!/usr/bin/env bash
set -e

# Locale
echo 'en_US.UTF-8 UTF-8' | sudo tee /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Default shell
sudo chsh -s /usr/bin/zsh "$USER"

# System updates + python3-venv for Mason (nvim)
sudo apt-get update && sudo apt-get install -y python3-pip python3-venv
