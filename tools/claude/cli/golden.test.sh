#!/usr/bin/env bash
# Golden-output tests for claude-cli: every subcommand's output — and, for
# the cases that write state, the state it leaves behind — is pinned against
# a stored snapshot in tools/claude/cli/testdata/golden/<slug>.out (+ .state).
# Same conventions as tools/claude/hooks/pretooluse-guard.test.sh and
# session-lifecycle.test.sh: counters, private temp dirs, no `set -e` (the
# test must reach the end and report every failure, not die on the first
# one).
#
# Usage:
#   bash tools/claude/cli/golden.test.sh            # compare against the goldens
#   bash tools/claude/cli/golden.test.sh --update   # (re)write the goldens from the current binary
# Builds the binary itself unless CLAUDE_CLI_BIN already points at one.
# Needs go and jq (jq is only for the bashhint suite this script also runs)
# and python3 (only to spawn a marker process for one pane-title case).
#
# The goldens were produced by the binary that matched main's now-deleted
# bash/python originals 71/71 on 2026-09-28 (commit bd3396b). This suite no
# longer runs that comparison — the originals are gone — it pins the
# binary's own output instead, so a future change has to be deliberate.
set -uo pipefail

CLI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$CLI_DIR/../../.." && pwd)"
TESTDATA="$CLI_DIR/testdata"
GOLDEN="$TESTDATA/golden"
BASHHINT_TEST="$REPO_ROOT/tools/claude/hooks/posttooluse-bashhint.test.sh"

UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1
mkdir -p "$GOLDEN"

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }
section() { printf '\n== %s ==\n' "$1"; }

command -v jq >/dev/null || { echo "нужен jq"; exit 2; }
command -v python3 >/dev/null || { echo "нужен python3 (для одного случая pane-title)"; exit 2; }

BIN="${CLAUDE_CLI_BIN:-}"
if [[ -z $BIN ]]; then
  BIN="$(mktemp -d)/claude-cli"
  (cd "$CLI_DIR" && go build -o "$BIN" .) || { echo "сборка claude-cli не удалась"; exit 2; }
fi
[[ -x $BIN ]] || { echo "не найден исполняемый $BIN"; exit 2; }

RUN="$(mktemp -d)"
trap 'rm -rf "$RUN"' EXIT

# byte_diff GOLDEN ACTUAL: identical -> rc 0, empty stdout; else rc 1 and one
# line describing the first difference (or the missing-golden case), ANSI
# escapes made visible.
byte_diff() {
  local golden="$1" actual="$2"
  if [[ ! -f $golden ]]; then
    printf 'no golden at %s (run with --update)' "$golden"
    return 1
  fi
  cmp -s "$golden" "$actual" && return 0
  local line
  line=$(diff "$golden" "$actual" 2>&1 | head -n1 | cat -v)
  printf '%s' "$line"
  return 1
}

# check_golden DESC SLUG ACTUAL_FILE: --update writes/overwrites
# testdata/golden/SLUG.out; otherwise compares byte for byte.
check_golden() {
  local desc="$1" slug="$2" actual="$3"
  local golden="$GOLDEN/$slug.out"
  if [[ $UPDATE -eq 1 ]]; then
    cp "$actual" "$golden"
    ok "$desc (golden written)"
    return
  fi
  local d rc
  d=$(byte_diff "$golden" "$actual"); rc=$?
  if [[ $rc -eq 0 ]]; then ok "$desc"; else bad "$desc" "$d"; fi
}

# check_golden_pair DESC SLUG ACTUAL_OUT ACTUAL_STATE: same, for cases that
# also pin the state the binary wrote (SLUG.out + SLUG.state).
check_golden_pair() {
  local desc="$1" slug="$2" a_out="$3" a_state="$4"
  local g_out="$GOLDEN/$slug.out" g_state="$GOLDEN/$slug.state"
  if [[ $UPDATE -eq 1 ]]; then
    cp "$a_out" "$g_out"
    cp "$a_state" "$g_state"
    ok "$desc (golden written)"
    return
  fi
  local d_out d_state rc_out rc_state
  d_out=$(byte_diff "$g_out" "$a_out"); rc_out=$?
  d_state=$(byte_diff "$g_state" "$a_state"); rc_state=$?
  if [[ $rc_out -eq 0 && $rc_state -eq 0 ]]; then
    ok "$desc"
  else
    bad "$desc" "out: $d_out | state: $d_state"
  fi
}

# ---------------------------------------------------------------------------
section "statusline: static cases (COLUMNS / glyphs / thresholds)"
# ---------------------------------------------------------------------------
# Shared session-badge fixture: a real ~/.claude/sessions snapshot recorded
# on this machine (no secrets — pid, sessionId, cwd, job names only), reused
# by every static case below via HOME, so the badge segment is pinned
# without depending on the live machine's current sessions.
SL_HOME="$TESTDATA/statusline/home"

run_statusline_case() {
  local desc="$1" slug="$2" json_file="$3"; shift 3
  local dtmp out
  dtmp="$RUN/sl-$$-$RANDOM"
  mkdir -p "$dtmp"
  out=$(env HOME="$SL_HOME" TMPDIR="$dtmp" "$@" "$BIN" statusline < "$json_file")
  printf '%s' "$out" > "$dtmp/actual.out"
  check_golden "$desc" "$slug" "$dtmp/actual.out"
}

run_statusline_case "wide 120, full segments"        "statusline-case01-basic"            "$TESTDATA/statusline/stdin/case01_basic.json"          COLUMNS=120
run_statusline_case "narrow <60"                      "statusline-case02-narrow-50"        "$TESTDATA/statusline/stdin/case02_narrow_50.json"      COLUMNS=50
run_statusline_case "narrow <80"                      "statusline-case03-narrow-70"        "$TESTDATA/statusline/stdin/case03_narrow_70.json"      COLUMNS=70
run_statusline_case "narrow <100"                     "statusline-case04-narrow-90"        "$TESTDATA/statusline/stdin/case04_narrow_90.json"      COLUMNS=90
run_statusline_case "ascii glyphs"                    "statusline-case05-ascii-glyphs"      "$TESTDATA/statusline/stdin/case05_ascii_glyphs.json"   COLUMNS=120 CLAUDE_STATUSLINE_GLYPHS=ascii
run_statusline_case "debug shows every segment"       "statusline-case06-debug-all"         "$TESTDATA/statusline/stdin/case06_debug_all.json"      COLUMNS=120 CLAUDE_STATUSLINE_DEBUG=1
run_statusline_case "no session_id"                   "statusline-case07-no-session"        "$TESTDATA/statusline/stdin/case07_no_session.json"     COLUMNS=120
run_statusline_case "fable model - orange"            "statusline-case08-fable-model"       "$TESTDATA/statusline/stdin/case08_fable_model.json"    COLUMNS=120
run_statusline_case "context bar red threshold"       "statusline-case09-ctx-red"           "$TESTDATA/statusline/stdin/case09_ctx_red.json"        COLUMNS=120
run_statusline_case "1M context window marker"        "statusline-case10-ctx-1m"            "$TESTDATA/statusline/stdin/case10_ctx_1M.json"         COLUMNS=120
run_statusline_case "five-hour window fully spent"    "statusline-case11-five-hour-over100" "$TESTDATA/statusline/stdin/case11_five_hour_over100.json" COLUMNS=120
run_statusline_case "no rate_limits object at all"    "statusline-case12-no-rate-limits"    "$TESTDATA/statusline/stdin/case12_no_rate_limits.json" COLUMNS=120
run_statusline_case "TERM=dumb falls back to ascii"   "statusline-case13-term-dumb"         "$TESTDATA/statusline/stdin/case13_term_dumb.json"      COLUMNS=120 TERM=dumb CLAUDE_STATUSLINE_GLYPHS=
run_statusline_case "non-default output style"        "statusline-case14-style-nondefault"  "$TESTDATA/statusline/stdin/case14_style_nondefault.json" COLUMNS=120
run_statusline_case "xhigh effort"                    "statusline-case15-xhigh-effort"      "$TESTDATA/statusline/stdin/case15_xhigh_effort.json"   COLUMNS=120
run_statusline_case "max effort"                      "statusline-case16-max-effort"        "$TESTDATA/statusline/stdin/case16_max_effort.json"     COLUMNS=120
run_statusline_case "unknown effort label falls back" "statusline-case17-unknown-effort"    "$TESTDATA/statusline/stdin/case17_unknown_effort.json" COLUMNS=120
run_statusline_case "custom agent suffix"             "statusline-case18-custom-agent"      "$TESTDATA/statusline/stdin/case18_custom_agent.json"   COLUMNS=120
printf '{}' > "$RUN/empty_payload.json"
run_statusline_case "empty payload {}"                "statusline-empty-payload"            "$RUN/empty_payload.json"                               COLUMNS=120

# ---------------------------------------------------------------------------
section "statusline: rate-limit history (time-relative — templated, not frozen)"
# ---------------------------------------------------------------------------
# These three depend on "now": a frozen absolute epoch would drift out of
# every window as real time passes, so the fixture is a template with
# __NOW_M<seconds>__ / __RESET__ placeholders, substituted with the actual
# run's clock right before use — exactly as before. What changes is the
# other direction: the binary has no clock override (checked statusline.go —
# it calls time.Now() directly), so the rendered clock text and the raw
# epochs the binary writes back to state are un-rendered to the same
# placeholders before they are compared with the golden file. That makes
# the golden byte-stable regardless of when the suite runs.
render_template() {
  local src="$1" dst="$2" now="$3" reset="$4"
  # __RESET__ is quoted in the JSON fixtures so they stay valid JSON for the
  # syntax lint (the quotes go with the placeholder); the state files carry
  # it bare, so both spellings are substituted — quoted first.
  sed -e "s/\"__RESET__\"/$reset/g" \
      -e "s/__RESET__/$reset/g" \
      -e "s/__NOW_M1800__/$((now - 1800))/g" \
      -e "s/__NOW_M1500__/$((now - 1500))/g" \
      -e "s/__NOW_M1200__/$((now - 1200))/g" \
      -e "s/__NOW_M900__/$((now - 900))/g" \
      -e "s/__NOW_M600__/$((now - 600))/g" \
      -e "s/__NOW_M300__/$((now - 300))/g" \
      "$src" > "$dst"
}

# The fixture's sample offsets sit exactly on statusline.go's window/
# trend-lag boundaries (900s, 300s — see limitWindow/idleWindow/trendLag),
# so a drift of even one second between this shell's `now` and the
# binary's own clock read can flip which side of a boundary a sample
# lands on and change which segment renders. CLAUDE_CLI_NOW pins the
# binary to the exact same `now` the fixture was rendered with.

# strip_clocks blanks out the rendered "H:MM" clock(s) — the reset time
# alone, or "reset -> eta" when the arrow fires — with a fixed placeholder.
# There is nowhere else in the output that looks like a clock, so a plain
# global regex is enough; the placeholder count is itself pinned by the
# fixture's fixed history, not by wall-clock time.
strip_clocks() {
  sed -E 's/[0-9]{1,2}:[0-9]{2}/__CLOCK__/g'
}

# unrender_state is render_template in reverse: turns the absolute
# epochs the binary read/wrote back into the same placeholders, so the
# golden .state file doesn't drift with wall-clock time.
unrender_state() {
  local content="$1" now="$2" reset="$3"
  printf '%s\n' "$content" \
    | sed -e "s/$reset/__RESET__/g" \
          -e "s/$((now - 1800))/__NOW_M1800__/g" \
          -e "s/$((now - 1500))/__NOW_M1500__/g" \
          -e "s/$((now - 1200))/__NOW_M1200__/g" \
          -e "s/$((now - 900))/__NOW_M900__/g" \
          -e "s/$((now - 600))/__NOW_M600__/g" \
          -e "s/$((now - 300))/__NOW_M300__/g"
}

run_statusline_history_case() {
  local desc="$1" slug="$2" json_tmpl="$3" state_dir="$4"; shift 4
  local now reset dtmp
  now=$(date +%s)
  reset=$((now + 3000))
  dtmp="$RUN/slh-$$-$RANDOM"
  mkdir -p "$dtmp/claude-limit" "$dtmp/json"
  render_template "$json_tmpl" "$dtmp/json/in.json" "$now" "$reset"
  if [[ -d $state_dir ]]; then
    render_template "$state_dir/claude-limit/five_hour" "$dtmp/claude-limit/five_hour" "$now" "$reset"
    render_template "$state_dir/claude-limit/five_hour.window" "$dtmp/claude-limit/five_hour.window" "$now" "$reset"
  fi
  local out
  out=$(env HOME="$SL_HOME" TMPDIR="$dtmp" CLAUDE_CLI_NOW="$now" "$@" "$BIN" statusline < "$dtmp/json/in.json")
  printf '%s' "$out" | strip_clocks > "$dtmp/actual.out"
  local five win
  five=$(cat "$dtmp/claude-limit/five_hour" 2>/dev/null || true)
  win=$(cat "$dtmp/claude-limit/five_hour.window" 2>/dev/null || true)
  {
    unrender_state "$five" "$now" "$reset"
    unrender_state "$win" "$now" "$reset"
  } > "$dtmp/actual.state"
  check_golden_pair "$desc" "$slug" "$dtmp/actual.out" "$dtmp/actual.state"
}

run_statusline_history_case "accelerating 5h burn -> negative dev, trend down" "statusline-case19-five-hour-accel" \
  "$TESTDATA/statusline/stdin/case19_five_hour_accel.json" "$TESTDATA/statusline/state/case19_accel" COLUMNS=120
run_statusline_history_case "decelerating 5h burn -> trend up" "statusline-case20-five-hour-decel" \
  "$TESTDATA/statusline/stdin/case20_five_hour_decel.json" "$TESTDATA/statusline/state/case20_decel" COLUMNS=120
run_statusline_history_case "week deviation, no five-hour history" "statusline-case21-week-negative-dev" \
  "$TESTDATA/statusline/stdin/case21_week_negative_dev.json" /nonexistent COLUMNS=120

section "statusline: multi-session spend total"
dtmp="$RUN/slm-$$"
mkdir -p "$dtmp/claude-sessions"
cp "$TESTDATA/statusline/state/case22_multisession/claude-sessions/"* "$dtmp/claude-sessions/"
out=$(env HOME="$SL_HOME" TMPDIR="$dtmp" COLUMNS=120 "$BIN" statusline < "$TESTDATA/statusline/stdin/case22_multisession_spend.json")
printf '%s' "$out" > "$dtmp/actual.out"
check_golden "own share / everyone's total, several session files" "statusline-case22-multisession" "$dtmp/actual.out"

# ---------------------------------------------------------------------------
section "sessions [full [session_id]]: recorded snapshot + edge cases"
# ---------------------------------------------------------------------------
run_sessions_case() {
  local desc="$1" slug="$2" home="$3"; shift 3
  local out
  out=$(HOME="$home" "$BIN" sessions "$@")
  printf '%s' "$out" > "$RUN/actual-sessions.out"
  check_golden "$desc" "$slug" "$RUN/actual-sessions.out"
}

REC_HOME="$TESTDATA/sessions/recorded"
run_sessions_case "bare mode on recorded snapshot" "sessions-bare-recorded" "$REC_HOME"
run_sessions_case "full mode on recorded snapshot" "sessions-full-recorded" "$REC_HOME" full
run_sessions_case "full mode, self_id excludes a recorded session" "sessions-full-recorded-selfid-excludes" "$REC_HOME" full "413069a1-4a04-442d-810d-9cc0bce44b7c"

# Edge cases need a currently-alive pid to exercise alive(): pid 1 (init /
# launchd) is alive on any Unix this runs on.
EDGE_HOME="$RUN/sessions-edge"
mkedge() { rm -rf "$EDGE_HOME"; mkdir -p "$EDGE_HOME/.claude/sessions"; }

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}' > "$EDGE_HOME/.claude/sessions/2.json"
echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"permission prompt"}' > "$EDGE_HOME/.claude/sessions/3.json"
run_sessions_case "running+waiting+approval all present (full)" "sessions-edge-running-waiting-approval-full" "$EDGE_HOME" full
run_sessions_case "bare mode omits running" "sessions-edge-bare-omits-running" "$EDGE_HOME"

mkedge
echo '{"kind":"bg","pid":1,"status":"idle"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "bg idle counts as waiting" "sessions-edge-bg-idle-waiting" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","spare":true}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "spare session excluded" "sessions-edge-spare-excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","parkedJobId":"x"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "parked session excluded" "sessions-edge-parked-excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"other","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "unknown kind excluded" "sessions-edge-unknown-kind-excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":999999997,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "implausible pid treated consistently" "sessions-edge-implausible-pid" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":"not-an-int","status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "non-integer pid excluded" "sessions-edge-noninteger-pid" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":123.0,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "float-typed pid excluded (python isinstance(int) fails)" "sessions-edge-float-pid" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "no self_id arg + no sessionId field -> None==None skip" "sessions-edge-no-selfid-arg" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","sessionId":""}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "explicit empty self_id matches empty sessionId" "sessions-edge-explicit-empty-selfid" "$EDGE_HOME" full ""

# ---------------------------------------------------------------------------
section "pane-title: shell shortcuts, container marker, node/tty lookup"
# ---------------------------------------------------------------------------
run_panetitle_case() {
  local desc="$1" slug="$2" pid="$3" cmd="$4" sess="$5" home="$6"; shift 6
  local out
  out=$(env HOME="$home" "$@" "$BIN" pane-title "$pid" "$cmd" "$sess" 2>&1)
  printf '%s' "$out" > "$RUN/actual-panetitle.out"
  check_golden "$desc" "$slug" "$RUN/actual-panetitle.out"
}

PT_HOME="$RUN/pt-home"
mkdir -p "$PT_HOME/.claude/sessions"
run_panetitle_case "zsh shortcut, no badge" "panetitle-zsh-no-badge" 12345 zsh mysession "$PT_HOME"
run_panetitle_case "bash shortcut, no badge" "panetitle-bash-no-badge" 12345 bash mysession "$PT_HOME"
run_panetitle_case "fish shortcut, no badge" "panetitle-fish-no-badge" 12345 fish mysession "$PT_HOME"
run_panetitle_case "other command, no badge" "panetitle-other-no-badge" 12345 nvim mysession "$PT_HOME"

echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}' > "$PT_HOME/.claude/sessions/1.json"
run_panetitle_case "other command, with badge" "panetitle-other-with-badge" 12345 nvim mysession "$PT_HOME"
rm -f "$PT_HOME/.claude/sessions/1.json"

# Real spawned processes exercise the actual `ps -o tty=` / `ps -t tty -o
# args=` lookup for real — no mocking needed. Output carries no pid, just
# the tty/args-derived text, so it stays golden-stable across runs.
python3 -c "import time; time.sleep(20)" claude-marker-parity-test &
REALPID=$!
sleep 0.3
run_panetitle_case "node cmd, real spawned process (ps tty lookup)" "panetitle-node-real-spawned" "$REALPID" node mysession "$PT_HOME"
kill "$REALPID" 2>/dev/null; wait "$REALPID" 2>/dev/null

sleep 20 &
REALPID2=$!
sleep 0.2
run_panetitle_case "digit-version cmd, real sleep process" "panetitle-digit-version-real-sleep" "$REALPID2" 999 mysession "$PT_HOME"
kill "$REALPID2" 2>/dev/null; wait "$REALPID2" 2>/dev/null

run_panetitle_case "node cmd, nonexistent pid" "panetitle-node-nonexistent-pid" 99999999 node mysession "$PT_HOME"

# ---------------------------------------------------------------------------
section "opsctx: ops-domain latch, 20+ recorded PreToolUse inputs"
# ---------------------------------------------------------------------------
run_opsctx_case() {
  local desc="$1" slug="$2" json_file="$3"
  local h out
  h="$RUN/opsctx-$$-$RANDOM"
  mkdir -p "$h"
  out=$(HOME="$h" "$BIN" opsctx < "$json_file")
  printf '%s' "$out" > "$RUN/actual-opsctx.out"
  check_golden "$desc" "$slug" "$RUN/actual-opsctx.out"
}

for f in "$TESTDATA"/opsctx/stdin/*.json; do
  b="$(basename "$f" .json)"
  run_opsctx_case "$b" "opsctx-$b" "$f"
done

# latch: second call in the same session+domain is silent.
ho="$RUN/opsctx-latch"
mkdir -p "$ho"
json="$TESTDATA/opsctx/stdin/latch_probe.json"
n1=$(HOME="$ho" "$BIN" opsctx < "$json")
n2=$(HOME="$ho" "$BIN" opsctx < "$json")
printf '%s' "$n1" > "$RUN/opsctx-latch-first.out"
if [[ -n $n2 ]]; then
  bad "latch: fires once per session+domain, silent on repeat" "second call not silent: [$n2]"
else
  check_golden "latch: fires once per session+domain, silent on repeat" "opsctx-latch-first-call" "$RUN/opsctx-latch-first.out"
fi

# 7-day cleanup: a stale latch file (mtime 10 days back) is deleted by the
# next ops-domain call.
hn="$RUN/opsctx-stale"
mkdir -p "$hn/.claude/.state/opsctx"
STALE_TS="$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)"
touch -t "$STALE_TS" "$hn/.claude/.state/opsctx/stale.remote"
HOME="$hn" "$BIN" opsctx < "$json" > /dev/null
left=$(ls "$hn/.claude/.state/opsctx" | sort | tr '\n' ',')
printf '%s' "$left" > "$RUN/opsctx-stale-left.out"
check_golden "stale (>7d) latch cleaned up" "opsctx-stale-cleanup" "$RUN/opsctx-stale-left.out"

# ---------------------------------------------------------------------------
section "bashhint: full existing behaviour suite against the binary"
# ---------------------------------------------------------------------------
if [[ -x $BASHHINT_TEST || -f $BASHHINT_TEST ]]; then
  bh_out=$(BASHHINT_HOOK="$BIN bashhint" bash "$BASHHINT_TEST" 2>&1)
  bh_summary=$(printf '%s\n' "$bh_out" | tail -n1)
  if printf '%s\n' "$bh_out" | tail -n1 | grep -q '0 fail$'; then
    ok "posttooluse-bashhint.test.sh against the binary ($bh_summary)"
  else
    bad "posttooluse-bashhint.test.sh against the binary" "$bh_summary"
    printf '%s\n' "$bh_out"
  fi
else
  bad "bashhint test script not found at $BASHHINT_TEST"
fi

# ---------------------------------------------------------------------------
printf '\n%d ok, %d fail\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
