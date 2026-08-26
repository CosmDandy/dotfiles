#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Disable Work Profile
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author CosmDandy

# Only work apps are closed — Telegram, Things, Timing, Ghostty and Arc stay open on
# purpose, they are needed outside work too.
# NOTE: `|| true` is required — killall on a process that is not running returns 1, and
# Raycast reported an execution error although the profile had worked.
pkill -f "Microsoft Teams" || true
killall Calendar || true
killall Mail || true
killall Obsidian || true
killall Claude || true
