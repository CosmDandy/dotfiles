#!/bin/bash

# Read JSON input
input=$(cat)

# Extract values
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d'.' -f1)
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# ANSI color codes
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

# Choose color based on percentage
ctx_color="$GREEN"
[ "$used_pct" -ge 50 ] 2>/dev/null && ctx_color="$YELLOW"
[ "$used_pct" -ge 75 ] 2>/dev/null && ctx_color="$RED"

# Output: "34% | Sonnet 4.5" with colors
printf "${ctx_color}%s%%${RESET} | ${BLUE}%s${RESET}" "$used_pct" "$model"
