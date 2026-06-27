#!/bin/bash

# ANSI color codes (actual ESC bytes via $'...' quoting)
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
GRAY=$'\033[90m'
BLUE=$'\033[34m'
RESET=$'\033[0m'

# Generate colored progress bar
# Args: $1=used_pct, $2=bar_length
# Returns: string with ANSI colored bar
generate_progress_bar() {
  local used_pct=$1
  local bar_length=$2
  local filled=$((used_pct * bar_length / 100))

  # Zone boundaries: 0-70% green, 70-80% yellow, 80%+ red
  local green_end=$((70 * bar_length / 100))
  local yellow_end=$((80 * bar_length / 100))

  # Calculate filled segments by zone
  local filled_green=0
  local filled_yellow=0
  local filled_red=0

  if [ $filled -le $green_end ]; then
    filled_green=$filled
  elif [ $filled -le $yellow_end ]; then
    filled_green=$green_end
    filled_yellow=$((filled - green_end))
  else
    filled_green=$green_end
    filled_yellow=$((yellow_end - green_end))
    filled_red=$((filled - yellow_end))
  fi

  # Calculate empty segments by zone
  local empty_green=0
  local empty_yellow=0
  local empty_red=0

  if [ $filled -lt $green_end ]; then
    empty_green=$((green_end - filled))
  fi

  if [ $filled -lt $yellow_end ]; then
    if [ $filled -lt $green_end ]; then
      empty_yellow=$((yellow_end - green_end))
    else
      empty_yellow=$((yellow_end - filled))
    fi
  fi

  if [ $filled -lt $bar_length ]; then
    if [ $filled -lt $yellow_end ]; then
      empty_red=$((bar_length - yellow_end))
    else
      empty_red=$((bar_length - filled))
    fi
  fi

  # Build bar segments (only if count > 0)
  local filled_green_bar=""
  local filled_yellow_bar=""
  local filled_red_bar=""
  local empty_green_bar=""
  local empty_yellow_bar=""
  local empty_red_bar=""

  [ $filled_green -gt 0 ] && filled_green_bar=$(printf '█%.0s' $(seq 1 $filled_green))
  [ $filled_yellow -gt 0 ] && filled_yellow_bar=$(printf '█%.0s' $(seq 1 $filled_yellow))
  [ $filled_red -gt 0 ] && filled_red_bar=$(printf '█%.0s' $(seq 1 $filled_red))
  [ $empty_green -gt 0 ] && empty_green_bar=$(printf '░%.0s' $(seq 1 $empty_green))
  [ $empty_yellow -gt 0 ] && empty_yellow_bar=$(printf '░%.0s' $(seq 1 $empty_yellow))
  [ $empty_red -gt 0 ] && empty_red_bar=$(printf '░%.0s' $(seq 1 $empty_red))

  # Return colored bar string
  printf "${GREEN}%s%s${YELLOW}%s%s${RED}%s%s${RESET}" \
    "$filled_green_bar" "$empty_green_bar" "$filled_yellow_bar" "$empty_yellow_bar" "$filled_red_bar" "$empty_red_bar"
}

# Read JSON input
input=$(cat)

# Extract values
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d'.' -f1)
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')

# Token usage (total for session)
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Calculate cache hit rate from current_usage
# cache_hit_rate = (cache_read / total_input) * 100
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cache_creation=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')

total_input=$((cache_read + input_tokens + cache_creation))
if [ "$total_input" -gt 0 ]; then
  cache_hit=$((cache_read * 100 / total_input))
else
  cache_hit=0
fi

# Format token counts (convert to k if >= 1000)
format_tokens() {
  local tokens=$1
  if [ "$tokens" -ge 1000 ]; then
    echo "$((tokens / 1000))k"
  else
    echo "$tokens"
  fi
}

input_str=$(format_tokens $total_input)
output_str=$(format_tokens $total_output)

# Choose color for context percentage (match progress bar: 70%/80% thresholds)
ctx_color="$GREEN"
[ "$used_pct" -ge 70 ] 2>/dev/null && ctx_color="$YELLOW"
[ "$used_pct" -ge 80 ] 2>/dev/null && ctx_color="$RED"

# Choose color for cache hit rate (0-20% bad/red, 20%+ good/green)
cache_color="$RED"
[ "$cache_hit" -ge 20 ] 2>/dev/null && cache_color="$GREEN"

# Terminal width (COLUMNS set by Claude Code v2.1.153+; fallback to wide)
cols=${COLUMNS:-100}

# Output style indicator (only when not the default style)
style_name=$(echo "$input" | jq -r '.output_style.name // "default"')
style_str=""
[ "$style_name" != "default" ] && style_str="${GRAY}⊙ ${style_name}${RESET}"

# Context warning at autocompact threshold (85%, matches CLAUDE_AUTOCOMPACT_PCT_OVERRIDE)
warn=""
if [ "$used_pct" -ge 85 ] 2>/dev/null; then
  ctx_color="$RED"
  warn=" ⚠"
fi

# ccusage cost/burn — only computed for the full (wide) tier (slow npx call)
compute_cost() {
  local cache CCBIN ccusage_json active cost burn cost_fmt burn_fmt burn_color burn_int
  # Кэш на 60с: ccusage дорогой (поднимает node + читает транскрипты). Без кэша он
  # спавнился на КАЖДЫЙ рендер статус-бара ×N сессий и стакался под нагрузкой.
  cache="${TMPDIR:-/tmp}/claude-statusline-ccusage.json"
  if [ -f "$cache" ] && [ "$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))" -lt 60 ]; then
    ccusage_json=$(cat "$cache")
  else
    touch "$cache" 2>/dev/null  # пометить свежим, чтобы параллельный рендер не запускал второй ccusage
    CCBIN=$(command -v ccusage 2>/dev/null)  # прямой бинарь вместо npx-резолва на каждый вызов
    if [ -n "$CCBIN" ]; then
      ccusage_json=$("$CCBIN" blocks --json 2>/dev/null)
    else
      ccusage_json=$(npx --prefer-offline ccusage blocks --json 2>/dev/null)
    fi
    [ -n "$ccusage_json" ] && printf '%s' "$ccusage_json" >| "$cache"
  fi
  [ -n "$ccusage_json" ] || return 0
  active=$(echo "$ccusage_json" | jq -c '[.blocks[] | select(.isActive==true)] | last // empty')
  [ -n "$active" ] || return 0
  cost=$(echo "$active" | jq -r '.costUSD')
  burn=$(echo "$active" | jq -r '.burnRate.costPerHour // 0')
  cost_fmt=$(printf "%.2f" "$cost")
  burn_fmt=$(printf "%.2f" "$burn")
  burn_color="$GREEN"
  burn_int=$(echo "$burn" | cut -d'.' -f1)
  [ "${burn_int:-0}" -ge 2 ] 2>/dev/null && burn_color="$YELLOW"
  [ "${burn_int:-0}" -ge 5 ] 2>/dev/null && burn_color="$RED"
  printf '$%s %s$%s/h%s' "$cost_fmt" "$burn_color" "$burn_fmt" "$RESET"
}

# Tiered rendering by terminal width
ctx_seg="${ctx_color}${used_pct}%${warn}${RESET}"
if [ "$cols" -lt 60 ]; then
  # compact (phone/narrow): model + short bar + context%
  bar=$(generate_progress_bar "$used_pct" 5)
  out="${BLUE}${model}${RESET} ${bar} ${ctx_seg}"
elif [ "$cols" -lt 90 ]; then
  # medium: + cache + tokens, no cost/burn
  bar=$(generate_progress_bar "$used_pct" 10)
  out="${BLUE}${model}${RESET} | ${bar} ${ctx_seg} | ${cache_color}◎ ${cache_hit}%${RESET} | ↑${input_str} ${GREEN}↓${output_str}${RESET}"
  [ -n "$style_str" ] && out="${out} | ${style_str}"
else
  # full: everything incl ccusage cost/burn
  bar=$(generate_progress_bar "$used_pct" 10)
  out="${BLUE}${model}${RESET} | ${bar} ${ctx_seg} | ${cache_color}◎ ${cache_hit}%${RESET} | ↑${input_str} ${GREEN}↓${output_str}${RESET}"
  [ -n "$style_str" ] && out="${out} | ${style_str}"
  cost_str=$(compute_cost)
  [ -n "$cost_str" ] && out="${out} | ${cost_str}"
fi
printf "%s" "$out"
