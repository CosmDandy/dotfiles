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

# Burn rate (tok/min) — считаем сами из дельт cumulative-токенов, которые
# Claude Code передаёт statusline'у: каждая сессия пишет сэмплы в свой
# state-файл, суммируем скорость по всем живым сессиям. Токены, не деньги:
# метрика не зависит от цены модели (ccusage в $/h горел красным на любой
# активности Fable). Пороги — первая прикидка, крутить здесь:
BURN_WINDOW=300      # окно усреднения, сек
BURN_YELLOW=50000    # tok/min: жёлтый
BURN_RED=150000      # tok/min: красный
compute_burn() {
  local dir sid now total f mtime first_ts first_tok last_ts last_tok span rate sum color
  dir="${TMPDIR:-/tmp}/claude-burn"
  mkdir -p "$dir" 2>/dev/null || return 0
  sid=$(echo "$input" | jq -r '.session_id // empty')
  [ -n "$sid" ] || return 0
  now=$(date +%s)
  total=$(echo "$input" | jq -r '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')
  f="$dir/$sid"
  # счётчик упал (компакция/перезапуск сессии) — базлайн заново
  if [ -f "$f" ]; then
    last_tok=$(tail -1 "$f" | cut -d' ' -f2)
    [ "${total:-0}" -lt "${last_tok:-0}" ] 2>/dev/null && : >| "$f"
  fi
  echo "$now $total" >> "$f"
  # оставить сэмплы окна + один базлайн старше окна (для полной дельты)
  awk -v now="$now" -v w="$BURN_WINDOW" '
    $1 < now-w { base=$0; next } { if (base != "") { print base; base="" } print }
  ' "$f" >| "$f.tmp" && mv "$f.tmp" "$f"
  sum=0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    case "$f" in *.tmp) continue ;; esac
    # мёртвая сессия: файл не обновлялся дольше окна — вычистить
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$((now - mtime))" -gt "$BURN_WINDOW" ]; then rm -f "$f"; continue; fi
    first_ts=$(head -1 "$f" | cut -d' ' -f1); first_tok=$(head -1 "$f" | cut -d' ' -f2)
    last_ts=$(tail -1 "$f" | cut -d' ' -f1);  last_tok=$(tail -1 "$f" | cut -d' ' -f2)
    span=$((last_ts - first_ts))
    [ "$span" -ge 30 ] || continue  # мало данных для скорости
    rate=$(( (last_tok - first_tok) * 60 / span ))
    [ "$rate" -gt 0 ] && sum=$((sum + rate))
  done
  [ "$sum" -gt 0 ] || return 0
  color="$GREEN"
  [ "$sum" -ge "$BURN_YELLOW" ] && color="$YELLOW"
  [ "$sum" -ge "$BURN_RED" ] && color="$RED"
  printf '%s🔥%s/m%s' "$color" "$(format_tokens "$sum")" "$RESET"
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
  # full: everything incl burn rate
  bar=$(generate_progress_bar "$used_pct" 10)
  out="${BLUE}${model}${RESET} | ${bar} ${ctx_seg} | ${cache_color}◎ ${cache_hit}%${RESET} | ↑${input_str} ${GREEN}↓${output_str}${RESET}"
  [ -n "$style_str" ] && out="${out} | ${style_str}"
  burn_str=$(compute_burn)
  [ -n "$burn_str" ] && out="${out} | ${burn_str}"
fi
printf "%s" "$out"
