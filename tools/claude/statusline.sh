#!/bin/bash

# Statusline for Claude Code: session JSON on stdin, one line on stdout.
# Identity and context on the left, spend and subscription limits on the right.

ESC=$'\033'
R="${ESC}[0m"
# Palette slots 0-15 only, so the line follows the terminal theme instead of
# hardcoded shades.
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"
BLUE="${ESC}[34m"
# Neutral for "on track" — green already means "room to accelerate" in these
# segments.
CYAN="${ESC}[36m"
# NOTE: secondary text is ANSI 11, not "bright black" (8) or faint. Solarized
# defines the secondary tone with different codes for its light and dark themes,
# and the theme switches automatically here; 8 gives a contrast of ~2.1 on dark
# against a readability floor of 3. Only 11 stays above it on both sides (3.37
# dark / 4.13 light).
GRAY="${ESC}[38;5;11m"
# 38;5;11 is not "bright yellow" here: under Solarized it is base00, the body text
# colour, and the theme follows the system — light by day, dark by night. So the
# shade stays, and what recedes is the WEIGHT: SGR 2 (faint) dims relative to
# whatever the foreground currently is, which survives both themes where an absolute
# grey cannot (238 sinks on dark, turns near-black on light — tried, wrong both ways).
DIM="${ESC}[38;5;11m"
SEP="${ESC}[2;38;5;11m"
MONEY="${ESC}[2;38;5;11m"

# NOTE: the red threshold must equal CLAUDE_AUTOCOMPACT_PCT_OVERRIDE — change
# them as a pair, or the bar turns red only after the compact and warns about
# nothing. Yellow sits 25 pp below to leave room to wrap up.
CTX_YELLOW=40
CTX_RED=65
BAR_LEN=10

# The cache is shown only when it actually dips — it sits at 85-95% normally,
# and an evergreen indicator carried no information.
CACHE_SHOW=80
CACHE_RED=50

# The 5h window is always visible: it drains in bursts (a batch of workflow
# agents eats tens of percent in minutes), and without a baseline the
# acceleration is noticed too late.
FIVEH_SHOW=0
# NOTE: no percentage threshold on the deviation on purpose. "How much is spent"
# and "will it last" are different questions, and tying the second to the first
# is always late: parallel agents drive the window to zero from 40%.
DEV_SHOW_SEC=3600    # more than an hour of slack — nothing to decide
DEV_FLAT_SEC=300     # band around zero where the deviation itself drives the colour
TREND_LAG=900        # how far back the deviation is compared against for the trend
TREND_MIN_SEC=300    # smaller shifts are noise
# The week is a budget, the 5h window only a speed limit — so the goal here is
# to sit at zero, and an underspend is as much a signal as an overspend.
WEEK_SECONDS=604800
WEEK_FLAT_SEC=43200  # ±half a day counts as on schedule
# NOTE: an hour is too short an arm against a week — extrapolation amplifies it
# ×168 and any early burst draws a deviation several times the truth.
WEEK_MIN_ELAPSED=43200
LIMIT_WINDOW=900     # rate averaging window, sec
IDLE_WINDOW=300      # silence longer than this means spending stopped

# NOTE: glyphs are drawn by the TERMINAL, not by the machine running this — a
# devcontainer is entered from the same Ghostty. Detection is impossible, so
# assume the font is there and fall back only on known non-graphical TERMs.
case "${CLAUDE_STATUSLINE_GLYPHS:-}" in
  nerd)  glyphs=nerd ;;
  ascii) glyphs=ascii ;;
  *)     case "${TERM:-}" in
           dumb|linux|vt[0-9]*|ansi|cons25|sun*) glyphs=ascii ;;
           *) glyphs=nerd ;;
         esac ;;
esac

if [ "$glyphs" = nerd ]; then
  # NOTE: octal UTF-8 bytes, not literals — private-use codepoints survive file
  # copying badly and were lost once already.
  G_THINK=$'\363\260\247\221'    # U+F09D1 md-brain
  G_FIVEH=$'\363\260\246\226'    # U+F0996 md-progress_clock
  G_WEEK=$'\363\260\250\263'     # U+F0A33 md-calendar_week
  G_APPROVE=$'\363\260\214\276'   # U+F033E md-lock — waiting for permission
  G_DEAD=$'\360\237\222\200'      # U+1F480 window fully spent
  G_ARROW=$'\342\237\266'         # U+27F6
  CAP_L=''
  CAP_R=''
  # NOTE: Nerd Font icons take TWO columns in font variants without the Mono
  # suffix. Without this correction the right block overflowed and Claude Code
  # cut the tail.
  GLYPH_COLS=2
else
  G_THINK='*'
  G_FIVEH='5h'
  G_WEEK='7d'
  G_APPROVE=''
  G_DEAD='!!'
  G_ARROW='->'
  CAP_L=''
  CAP_R=''
  GLYPH_COLS=1
fi

# Effort marks exactly as Claude Code's own /effort menu shows them. Plain
# Unicode, one column, so they are outside the width correction above.
# NOTE: ultracode (✦) does not arrive as its own level — it reports as xhigh.
G_EFFORT_LOW=$'\342\227\213'    # U+25CB
G_EFFORT_MED=$'\342\227\220'    # U+25D0
G_EFFORT_HIGH=$'\342\227\217'   # U+25CF
G_EFFORT_XHI=$'\342\227\211'    # U+25C9
G_EFFORT_MAX=$'\342\227\210'    # U+25C8

# Default and low levels stay grey; only what burns noticeably more is coloured.
set_effort_parts() {
  case "$1" in
    low)    eff_glyph=$G_EFFORT_LOW;  eff_label=Low;    eff_color=$GRAY ;;
    medium) eff_glyph=$G_EFFORT_MED;  eff_label=Medium; eff_color=$GRAY ;;
    high)   eff_glyph=$G_EFFORT_HIGH; eff_label=High;   eff_color=$GRAY ;;
    xhigh)  eff_glyph=$G_EFFORT_XHI;  eff_label=xHigh;  eff_color=$YELLOW ;;
    max)    eff_glyph=$G_EFFORT_MAX;  eff_label=Max;    eff_color=$RED ;;
    *)      eff_glyph=''; eff_label=$1; eff_color=$GRAY ;;
  esac
}

# CLAUDE_STATUSLINE_DEBUG=1 shows every segment, ignoring the hide thresholds.
DEBUG_ALL="${CLAUDE_STATUSLINE_DEBUG:-}"

input=$(cat)

# One jq call instead of fifteen: a fork per field cost ~130 ms against a 300 ms
# debounce.
# NOTE: the field order here and in the read below must stay in sync.
# NOTE: the separator is 0x1F, NOT a tab — IFS collapses consecutive whitespace,
# so with @tsv an empty field (no agent, no effort) ate a position and shifted
# everything left.
IFS=$'\037' read -r used_pct model ctx_size cache_read input_tokens cache_creation \
  style_name effort thinking agent cost_usd \
  five_pct100 five_reset week_pct week_reset sid <<EOF
$(echo "$input" | jq -r '[
  (.context_window.used_percentage // 0 | floor),
  (.model.display_name // "Claude"),
  (.context_window.context_window_size // 0),
  (.context_window.current_usage.cache_read_input_tokens // 0),
  (.context_window.current_usage.input_tokens // 0),
  (.context_window.current_usage.cache_creation_input_tokens // 0),
  (.output_style.name // "default"),
  (.effort.level // ""),
  (if .thinking.enabled then "1" else "" end),
  (.agent.name // ""),
  ((.cost.total_cost_usd // 0) * 100 | floor),
  (if .rate_limits.five_hour.used_percentage == null then ""
   else (.rate_limits.five_hour.used_percentage * 100 | floor) end),
  (.rate_limits.five_hour.resets_at // ""),
  (if .rate_limits.seven_day.used_percentage == null then ""
   else (.rate_limits.seven_day.used_percentage | floor) end),
  (.rate_limits.seven_day.resets_at // ""),
  (.session_id // "")
] | map(tostring) | join("")')
EOF

cols=${COLUMNS:-100}
# NOTE: Claude Code adds its own padding on top of COLUMNS, so the last column
# cannot be used — the tail gets cut with an ellipsis.
#
# The wider margin exists for one thing only: the Remote Control chip Claude Code
# parks in the right corner. Without the bridge there is no chip and the reserved
# space is just a hole, so the line hugs the edge instead.
#
# Whether THIS session holds a bridge is answered by ~/.claude.json: every live one
# is an entry in replBridgePlaceholders carrying the pid that owns it. state.json
# does not answer it — a session running interactively has no job directory at all,
# and bridgeSessionId there only records that a bridge existed when the job was
# written. So walk up from this script to the owning `claude` process and see
# whether its pid is among them.
rc_margin=2
bridge_pids=$(jq -r '(.replBridgePlaceholders // {}) | .[].pid // empty' "$HOME/.claude.json" 2>/dev/null)
if [ -n "$bridge_pids" ]; then
  probe=$$
  hops=0
  while [ "$hops" -lt 6 ] && [ "${probe:-0}" -gt 1 ]; do
    case "
$bridge_pids
" in
      *"
$probe
"*) rc_margin=5; break ;;
    esac
    probe=$(ps -o ppid= -p "$probe" 2>/dev/null | tr -d ' ')
    hops=$((hops + 1))
  done
fi
RIGHT_MARGIN=${CLAUDE_STATUSLINE_MARGIN:-$rc_margin}

# --- context bar -------------------------------------------------------------

EIGHTHS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉')

# Block bar in theme colours; the last occupied cell is filled with an eighth,
# giving 1/8-cell precision at the same width.
render_bar() {
  local pct=$1 len=$2
  local eighths=$(( pct * len * 8 / 100 ))
  local full=$(( eighths / 8 ))
  local frac=$(( eighths % 8 ))
  local g_cells=$(( CTX_YELLOW * len / 100 ))
  local y_cells=$(( CTX_RED * len / 100 ))
  local i c out="" first="" last=""

  for ((i = 0; i < len; i++)); do
    if   [ "$i" -lt "$g_cells" ]; then c=$GREEN
    elif [ "$i" -lt "$y_cells" ]; then c=$YELLOW
    else                               c=$RED
    fi
    [ "$i" -eq 0 ] && first=$c
    last=$c
    if [ "$i" -lt "$full" ]; then
      out="${out}${c}█"
    elif [ "$i" -eq "$full" ] && [ "$frac" -gt 0 ]; then
      out="${out}${c}${EIGHTHS[$frac]}"
    else
      out="${out}${c}░"
    fi
  done

  if [ -n "$CAP_L" ]; then
    printf '%s%s%s%s%s%s' "$first" "$CAP_L" "$out" "$last" "$CAP_R" "$R"
  else
    printf '%s%s' "$out" "$R"
  fi
}

# --- limits ------------------------------------------------------------------

# NOTE: minutes are mandatory — this is a deadline, and truncating to the hour
# lies by almost an hour, always in the direction of "less time than you have".
# BSD and GNU date read an epoch with different flags.
fmt_clock() {
  local ts=$1
  date -r "$ts" +'%-H:%M' 2>/dev/null || date -d "@$ts" +'%-H:%M' 2>/dev/null
}

# Signed deviation: "+40м" is slack left at reset, "-12м" is how much earlier it
# runs out.
fmt_dev() {
  local s=$1 sign=+
  if [ "$s" -lt 0 ]; then sign=-; s=$(( -s )); fi
  # Under a minute either way is "just barely", not "minus zero".
  if [ "$s" -lt 60 ]; then printf '0м'; return; fi
  if [ "$s" -ge 3600 ]; then
    printf '%s%dч%02dм' "$sign" "$((s / 3600))" "$(((s % 3600) / 60))"
  else
    printf '%s%dм' "$sign" "$((s / 60))"
  fi
}

# Same for the weekly window, in days. The tenth matters: whole days are too
# coarse on a week-long arm and hours are unreadable.
fmt_dev_days() {
  local s=$1 sign=+ t
  if [ "$s" -lt 0 ]; then sign=-; s=$(( -s )); fi
  t=$(( s * 10 / 86400 ))
  if [ "$t" -eq 0 ]; then printf '0.0д'; return; fi
  printf '%s%d.%dд' "$sign" "$((t / 10))" "$((t % 10))"
}

# Will the current rate last until the 5h window resets. Answers with a signed
# deviation in seconds; empty when there is no rate (idle, or too short an arm).
# Percentages are kept in hundredths, and the sample file is shared across
# sessions — the limit is per-account, not per-session.
# NOTE: called through $(...), so the only way out is stdout. The percentage and
# reset it prints may differ from the arguments: a lagging session takes the
# shared ones.
five_hour_dev() {
  local pct100=$1 reset=$2 now=$3
  local dir f wf prev_reset last first_ts first_pct last_ts last_pct idle_pct span delta
  local pb_ts pb_pct pl_ts pl_pct pspan pdev dev="" trend=""
  dir="${TMPDIR:-/tmp}/claude-limit"
  mkdir -p "$dir" 2>/dev/null || { printf '%s %s' "$pct100" "$reset"; return 0; }
  f="$dir/five_hour"
  [ -n "$reset" ] || { printf '%s %s' "$pct100" "$reset"; return 0; }
  # NOTE: window rollover is detected by resets_at, NOT by the percentage
  # dropping. Sessions update the payload at their own pace and an idle one
  # holds a snapshot for hours, so any drop threshold fires spuriously and wipes
  # the history. resets_at changes exactly at the reset and only forward.
  wf="$f.window"
  prev_reset=0
  [ -f "$wf" ] && read -r prev_reset < "$wf"
  prev_reset=${prev_reset:-0}
  if [ "$reset" -gt "$prev_reset" ] 2>/dev/null; then
    printf '%s\n' "$reset" >| "$wf"
    printf '%s %s\n' "$now" "$pct100" >| "$f"      # new window — new baseline
    printf '%s %s' "$pct100" "$reset"; return 0
  fi
  last=0
  [ -f "$f" ] && last=$(tail -1 "$f" | cut -d' ' -f2)
  last=${last:-0}
  # NOTE: a stale snapshot is not written to history but the calculation
  # continues — the limit is per-account, so an idle session must show the same
  # picture as an active one. An early return here used to leave lagging windows
  # with no forecast at all.
  if [ "$reset" -lt "$prev_reset" ] 2>/dev/null; then
    reset=$prev_reset
    pct100=$last
  elif [ "${pct100:-0}" -lt "$last" ] 2>/dev/null; then
    pct100=$last
  else
    # NOTE: append only. Rewriting the file through `awk > tmp && mv` on every
    # tick let parallel sessions overwrite each other, so the history lived
    # seconds and never reached span >= 60. A short append is atomic; the window
    # is selected on READ.
    printf '%s %s\n' "$now" "$pct100" >> "$f"
  fi
  # Baseline: the last sample older than the window, else the earliest inside
  # it. idle_pct is the percentage at the IDLE_WINDOW boundary; the p* quadruple
  # is the same window shifted TREND_LAG back, which is what the trend arrow
  # compares against.
  read -r first_ts first_pct last_ts last_pct idle_pct pb_ts pb_pct pl_ts pl_pct <<EOF
$(awk -v now="$now" -v w="$LIMIT_WINDOW" -v iw="$IDLE_WINDOW" -v lag="$TREND_LAG" '
    {
      # NOTE: the baseline is taken outside the window so the arm is at least as
      # long as it — but never further than a second window. After an hour of
      # idling the arm would stretch across the whole pause, dividing a burst by
      # it and understating the rate several-fold, which promises slack that is
      # not there.
      if ($1 < now-w) { if ($1 >= now-2*w) { b_ts=$1; b_pct=$2 } }
      else {
        if (f_ts == "") { f_ts=$1; f_pct=$2 }
        if ($1 < now-iw) { i_pct=$2 }
        l_ts=$1; l_pct=$2
      }
      if ($1 < now-lag-w) { if ($1 >= now-lag-2*w) { pb_ts=$1; pb_pct=$2 } }
      else if ($1 <= now-lag) {
        if (pf_ts == "") { pf_ts=$1; pf_pct=$2 }
        pl_ts=$1; pl_pct=$2
      }
    }
    END {
      if (b_ts == "") { b_ts=f_ts; b_pct=f_pct }
      if (i_pct == "") { i_pct=b_pct }
      if (pb_ts == "") { pb_ts=pf_ts; pb_pct=pf_pct }
      if (b_ts == "" || l_ts == "") exit
      # A short history has no previous window at all — zeros disable the trend.
      if (pb_ts == "" || pl_ts == "") { pb_ts=0; pb_pct=0; pl_ts=0; pl_pct=0 }
      print b_ts, b_pct, l_ts, l_pct, i_pct, pb_ts, pb_pct, pl_ts, pl_pct
    }' "$f")
EOF
  [ -n "$last_pct" ] || { printf '%s %s' "$pct100" "$reset"; return 0; }
  # keep the file bounded; rare enough that a race does not matter
  if [ "$(wc -l < "$f")" -gt 600 ] 2>/dev/null; then
    tail -100 "$f" >| "$f.tmp" && mv "$f.tmp" "$f"
  fi
  # NOTE: the percentage arrives in whole points, so on a short arm a one-step
  # delta changes the rate several-fold and the forecast flickers. Both time and
  # a visible change are required: 180 seconds and one whole point.
  span=$((last_ts - first_ts))
  delta=$((last_pct - first_pct))
  # NOTE: idle detection — the sliding window does not notice a stop by itself,
  # it keeps dividing an old burst by the full arm and reporting a brisk rate.
  if [ "$((last_pct - idle_pct))" -gt 0 ] 2>/dev/null \
     && [ "$span" -ge 180 ] && [ "$delta" -ge 100 ]; then
    # How long the remainder lasts MINUS the wait for the reset.
    # NOTE: the rate is deliberately not computed as its own value — rounding
    # hundredths of a percent per minute ate up to 4% and swung the deviation by
    # seven minutes between ticks. One division for the whole expression, no
    # intermediate loss.
    dev=$(( (10000 - pct100) * span / delta - (reset - now) ))
    # NOTE: the trend compares the deviation with itself TREND_LAG ago. Against
    # "five minutes ago" a whole-point step gives either zero or a jump, and the
    # colour twitches.
    pspan=$((pl_ts - pb_ts))
    if [ "$pb_ts" -gt 0 ] && [ "$pspan" -ge 180 ] \
       && [ "$((pl_pct - pb_pct))" -ge 100 ]; then
      pdev=$(( (10000 - pl_pct) * pspan / (pl_pct - pb_pct) - (reset - now + TREND_LAG) ))
      if [ "$((dev - pdev))" -gt "$TREND_MIN_SEC" ]; then trend="up"
      elif [ "$((pdev - dev))" -gt "$TREND_MIN_SEC" ]; then trend="down"
      else trend="flat"; fi
    fi
  fi
  printf '%s %s %s %s' "$pct100" "$reset" "$dev" "$trend"
}

# Claude Code puts subscription limits straight into the payload — no network,
# no cache, and it works unchanged in a devcontainer. The field exists only on
# Claude.ai Pro/Max and only after the first API response; the windows are
# independent.
compute_limits() {
  local now=$1 want_eta=$2 want_week=${3:-1}
  local five_pct dev trend color elapsed week_dev five_seg="" week_seg="" segs="" eta

  if [ -n "$five_pct100" ]; then
    read -r five_pct100 five_reset dev trend <<EOF2
$(five_hour_dev "$five_pct100" "$five_reset" "$now")
EOF2
    five_pct=$((five_pct100 / 100))
    if [ "$five_pct" -ge "$FIVEH_SHOW" ] || [ -n "$DEBUG_ALL" ]; then
      # NOTE: the colour follows the TREND, not the position — the sign is
      # already in the number. That gives two independent measurements in one
      # segment: "-12м" in red is "not going to make it and accelerating", in
      # green "not going to make it but already slowing". With no trend yet the
      # colour falls back to the sign.
      color="$DIM"
      case "$trend" in
        up)   color="$GREEN" ;;      # deviation growing — slowing down
        down) color="$RED" ;;        # shrinking — accelerating
        flat) color="$CYAN" ;;
        *)    if [ -n "$dev" ]; then
                if [ "$dev" -gt "$DEV_FLAT_SEC" ]; then color="$GREEN"
                elif [ "$dev" -lt "-$DEV_FLAT_SEC" ]; then color="$RED"
                else color="$CYAN"; fi
              fi ;;
      esac
      if [ "$five_pct" -ge 100 ]; then
        # Window fully spent: only the release time still matters.
        five_seg="${RED}${G_DEAD} you lose"
        [ -n "$five_reset" ] && five_seg="${five_seg} ($(fmt_clock "$five_reset"))"
        five_seg="${five_seg}${R}"
      else
        # NOTE: the arrow is added only for a negative deviation. reset+dev is
        # then the moment we hit 0% BEFORE the real reset; with a positive dev
        # it would land after the reset, i.e. describe a window that opens
        # before it is exhausted.
        five_seg="${color}${G_FIVEH} ${five_pct}%"
        eta=""
        if [ -n "$dev" ] && [ "$dev" -lt "$DEV_SHOW_SEC" ] && [ "$want_eta" -eq 1 ]; then
          five_seg="${five_seg} $(fmt_dev "$dev")"
          [ -n "$five_reset" ] && [ "$dev" -lt 0 ] && eta=$(( five_reset + dev ))
        fi
        if [ -n "$five_reset" ]; then
          if [ -n "$eta" ]; then
            five_seg="${five_seg} ($(fmt_clock "$five_reset") ${G_ARROW} $(fmt_clock "$eta"))"
          else
            five_seg="${five_seg} ($(fmt_clock "$five_reset"))"
          fi
        fi
        five_seg="${five_seg}${R}"
      fi
    fi
  fi

  if [ -n "$week_pct" ] && [ "$want_week" -eq 1 ]; then
    # NOTE: the weekly deviation is a comparison against a LINEAR schedule, not
    # an extrapolated rate — dividing by the percentage produced +53d and -3.8d
    # out of nowhere on a small percentage or a short arm. Only a shortfall is
    # shown: the goal is to consume the subscription, so a surplus interests
    # nobody.
    color="$DIM"
    week_dev=""
    if [ -n "$week_reset" ]; then
      # window = [resets_at - 7d, resets_at]
      elapsed=$(( WEEK_SECONDS - (week_reset - now) ))
      if [ "$elapsed" -ge "$WEEK_MIN_ELAPSED" ]; then
        dev=$(( elapsed - week_pct * WEEK_SECONDS / 100 ))
        if [ "$dev" -lt 0 ]; then
          week_dev=$dev
          [ "$dev" -lt "-$WEEK_FLAT_SEC" ] && color="$RED"
        fi
      fi
    fi
    week_seg="${color}${G_WEEK} ${week_pct}%"
    [ -n "$week_dev" ] && week_seg="${week_seg} $(fmt_dev_days "$week_dev")"
    week_seg="${week_seg}${R}"
  fi

  segs="$five_seg"
  if [ -n "$week_seg" ]; then
    if [ -n "$segs" ]; then segs="${segs} ${SEP}·${R} ${week_seg}"; else segs="$week_seg"; fi
  fi
  printf '%s' "$segs"
}

# --- alignment ---------------------------------------------------------------

# NOTE: visible width. ANSI sequences take no space and ${#s} counts codepoints,
# but a Nerd Font icon is one codepoint over GLYPH_COLS columns — the undercount
# accumulated and pushed the right block off the edge.
vis_width() {
  local s t n=0 g
  s=$(printf '%s' "$1" | sed "s/${ESC}\\[[0-9;]*m//g")
  n=${#s}
  if [ "$GLYPH_COLS" -gt 1 ]; then
    for g in "$G_THINK" "$G_FIVEH" "$G_WEEK" "$G_APPROVE" "$G_DEAD"; do
      [ -n "$g" ] || continue
      t=${s//"$g"/}
      n=$(( n + (${#s} - ${#t}) * (GLYPH_COLS - 1) ))
    done
  fi
  printf '%s' "$n"
}

# The right block hugs the terminal edge; when the line is too short both halves
# are joined into one ribbon, which beats wrapping onto a second line.
join_edges() {
  local left=$1 right=$2 gap
  if [ -z "$right" ]; then printf '%s' "$left"; return; fi
  gap=$(( cols - RIGHT_MARGIN - $(vis_width "$left") - $(vis_width "$right") ))
  if [ "$gap" -lt 2 ]; then
    printf '%s %s·%s %s' "$left" "$SEP" "$R" "$right"
  else
    printf '%s%*s%s' "$left" "$gap" '' "$right"
  fi
}

# --- segments ----------------------------------------------------------------

now=$(date +%s)

# Model block: [brain] Model [1M] [· effort] [▸ custom agent].
# NOTE: the 1M fact comes from context_window_size, not from the display name —
# that one reads "Opus 5 (1M context)" today and is Anthropic's to rename.
model_str="${model%% (*}"
# 1M is a property of the window, not part of the name: glued to the model in the
# same blue it read as "Opus 5 1M", one title. Faint separates the fact from the name.
ctx_mark=""
[ "${ctx_size:-0}" -ge 1000000 ] 2>/dev/null && ctx_mark="${SEP} 1M${R}"
model_seg="${BLUE}${model_str}${R}${ctx_mark}"
[ -n "$thinking" ] && model_seg="${BLUE}${G_THINK} ${model_str}${R}${ctx_mark}"
# Narrow variant of the same block, without effort.
model_seg_slim="$model_seg"
if [ -n "$effort" ]; then
  set_effort_parts "$effort"
  if [ -n "$eff_glyph" ]; then
    model_seg="${model_seg}${SEP} · ${R}${eff_color}${eff_glyph} ${eff_label}${R}"
  else
    model_seg="${model_seg}${SEP} · ${R}${eff_label}${R}"
  fi
fi
# the base agent is called "claude" — not information, so only custom ones are
# shown
case "$agent" in
  ""|claude|Claude) ;;
  *) model_seg="${model_seg}${GRAY} ▸ ${agent}${R}"
     model_seg_slim="${model_seg_slim}${GRAY} ▸ ${agent}${R}" ;;
esac

# Context
ctx_color=$GREEN
[ "$used_pct" -ge "$CTX_YELLOW" ] 2>/dev/null && ctx_color=$YELLOW
[ "$used_pct" -ge "$CTX_RED" ] 2>/dev/null && ctx_color=$RED
bar=$(render_bar "$used_pct" "$BAR_LEN")
ctx_seg="${bar} ${ctx_color}${used_pct}%${R}"

# Cache: only when it dipped, and only when there is something to divide
# (current_usage is empty at session start and right after /compact).
total_input=$((cache_read + input_tokens + cache_creation))
cache_seg=""
if [ "$total_input" -gt 0 ]; then
  cache_hit=$((cache_read * 100 / total_input))
  if [ "$cache_hit" -lt "$CACHE_SHOW" ] || [ -n "$DEBUG_ALL" ]; then
    cache_color=$YELLOW
    [ "$cache_hit" -lt "$CACHE_RED" ] && cache_color=$RED
    [ "$cache_hit" -ge "$CACHE_SHOW" ] && cache_color=$GREEN
    cache_seg="${cache_color}◎ ${cache_hit}%${R}"
  fi
fi

# Whole dollars: cents cost four columns and decide nothing. Rounded, not truncated,
# so a session at 90 cents reads $1 rather than $0.
fmt_money() { printf '$%d' "$((($1 + 50) / 100))"; }

# Money and sessions in one block: how many of us, my share, everyone's total.
# NOTE: the 5h/7d limits are per-account but the cost in the payload is
# per-session, so with several windows open only one share is visible. Each
# session writes its own file; alive means touched within SESSION_TTL.
SESSION_TTL=90
alive=0
total=0
if [ -n "$sid" ]; then
  sdir="${TMPDIR:-/tmp}/claude-sessions"
  if mkdir -p "$sdir" 2>/dev/null; then
    printf '%s\n' "${cost_usd:-0}" >| "$sdir/$sid"
    for sf in "$sdir"/*; do
      [ -f "$sf" ] || continue
      # NOTE: GNU form FIRST — BSD rejects -c with an empty stdout, while GNU
      # reads -f as --file-system and prints a filesystem block into stdout
      # before failing.
      mtime=$(stat -c %Y "$sf" 2>/dev/null || stat -f %m "$sf" 2>/dev/null || echo 0)
      if [ "$((now - mtime))" -gt "$SESSION_TTL" ]; then
        rm -f "$sf"          # session closed or long silent
        continue
      fi
      alive=$((alive + 1))
      read -r c < "$sf" 2>/dev/null || c=0
      total=$((total + ${c:-0}))
    done
  fi
fi

# What the other sessions are doing, not how many exist: running, waiting for an
# answer, waiting for permission. Same counters as the tmux status line, read from
# ~/.claude/jobs/*/state.json. A bare count of open windows said nothing — five
# idle sessions and five busy ones printed the same "5" — so when there is nothing
# in these three states, nothing is printed, and the block falls back to this
# session's own cost.
# Located relative to this file, not to $HOME: the clone is ~/.dotfiles on the Mac
# and ~/dotfiles inside a devcontainer, and ~/.claude/statusline.sh is a symlink
# into it either way.
_self=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
_repo=$(dirname "$(dirname "$(dirname "$_self")")")
claude_badge=$("$_repo/tools/claude/claude-sessions.py" full 2>/dev/null)

cost_seg=""
if [ -n "$claude_badge" ]; then
  # the badge brings its own colours — wrapping it in one would flatten all three
  cost_seg="${claude_badge} ${SEP}·${R} ${MONEY}$(fmt_money "${cost_usd:-0}")/$(fmt_money "$total")${R}"
elif [ "${cost_usd:-0}" -gt 0 ] 2>/dev/null; then
  cost_seg="${MONEY}$(fmt_money "$cost_usd")${R}"
fi

style_seg=""
[ "$style_name" != "default" ] && style_seg="${GRAY}⊙ ${style_name}${R}"

# --- render ------------------------------------------------------------------

sep="${SEP}·${R}"

add() {  # $1=accumulator $2=segment
  if [ -z "$2" ]; then printf '%s' "$1"
  elif [ -z "$1" ]; then printf '%s' "$2"
  else printf '%s %s %s' "$1" "$sep" "$2"
  fi
}

# Order of eviction as the line narrows, least needed first: cache → price and
# session count → weekly window → effort. Model, context and the 5h window
# survive to the end.
if [ "$cols" -lt 60 ]; then
  limits=$(compute_limits "$now" 0 0)   # called for the sample accumulation alone
  out=$(add "$model_seg_slim" "$ctx_seg")
elif [ "$cols" -lt 80 ]; then
  limits=$(compute_limits "$now" 0 0)
  left=$(add "$model_seg_slim" "$ctx_seg")
  out=$(join_edges "$left" "$limits")
elif [ "$cols" -lt 100 ]; then
  limits=$(compute_limits "$now" 0 1)
  left=$(add "$model_seg_slim" "$ctx_seg")
  right=$(add "$cost_seg" "$limits")
  out=$(join_edges "$left" "$right")
else
  limits=$(compute_limits "$now" 1)
  left=$(add "$model_seg" "$ctx_seg")
  [ -n "$style_seg" ] && left=$(add "$left" "$style_seg")
  right=$(add "$cache_seg" "$cost_seg")
  right=$(add "$right" "$limits")
  out=$(join_edges "$left" "$right")
fi
printf '%s' "$out"
