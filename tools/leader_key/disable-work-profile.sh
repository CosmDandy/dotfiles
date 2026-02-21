#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Disable Work Profile
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author CosmDandy

killall WakaTime
pkill -f "Microsoft Teams"
killall Calendar
killall Mail
killall Obsidian
killall Claude
