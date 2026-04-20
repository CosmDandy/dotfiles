#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[docker-cleanup]"

echo "$LOG_PREFIX Removing dangling images..."
docker image prune -f

echo "$LOG_PREFIX Removing unused volumes..."
docker volume prune -f

echo "$LOG_PREFIX Removing build cache..."
docker builder prune -f --keep-storage 5G

echo "$LOG_PREFIX Disk usage after cleanup:"
docker system df

echo "$LOG_PREFIX Done"
