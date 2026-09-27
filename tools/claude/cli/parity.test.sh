#!/usr/bin/env bash
# Parity tests for claude-cli: every subcommand must reproduce the script it
# replaces byte for byte on the same recorded inputs. Same conventions as
# tools/claude/hooks/pretooluse-guard.test.sh and session-lifecycle.test.sh:
# counters, private temp dirs, no `set -e` (the test must reach the end and
# report every failure, not die on the first one).
#
# Usage: bash tools/claude/cli/parity.test.sh
# Builds the binary itself unless CLAUDE_CLI_BIN already points at one.
# Needs go, jq, python3 (the python3 is only for the OLD claude-sessions.py
# comparisons — the point of this binary is that production no longer needs
# it).
set -uo pipefail

CLI_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$CLI_DIR/../../.." && pwd)"
TESTDATA="$CLI_DIR/testdata"

OLD_STATUSLINE="$REPO_ROOT/tools/claude/statusline.sh"
OLD_SESSIONS="$REPO_ROOT/tools/claude/claude-sessions.py"
OLD_PANETITLE="$REPO_ROOT/tools/tmux/pane-title.sh"
OLD_OPSCTX="$REPO_ROOT/tools/claude/hooks/pretooluse-opsctx.sh"
BASHHINT_TEST="$REPO_ROOT/tools/claude/hooks/posttooluse-bashhint.test.sh"

# This suite gated the switch commit that deleted the five originals (see
# git log for the last real run's pass count — 70/70 at switch time, 71/71
# after a follow-up fix added a regression case). Once the originals are
# gone there is nothing left to compare against, so this is a deliberate
# no-op, not a failure — the historical proof lives in git log, not in a
# test that would otherwise fail forever.
if [[ ! -f $OLD_STATUSLINE ]]; then
  echo "originals already removed (see git log for the last pre-switch parity run) — nothing to compare, skipping"
  exit 0
fi

pass=0 fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [[ $# -gt 1 ]] && printf '        %s\n' "$2"; }
section() { printf '\n== %s ==\n' "$1"; }

command -v jq >/dev/null || { echo "нужен jq"; exit 2; }
command -v python3 >/dev/null || { echo "нужен python3 (для сравнения со старым claude-sessions.py)"; exit 2; }

BIN="${CLAUDE_CLI_BIN:-}"
if [[ -z $BIN ]]; then
  BIN="$(mktemp -d)/claude-cli"
  (cd "$CLI_DIR" && go build -o "$BIN" .) || { echo "сборка claude-cli не удалась"; exit 2; }
fi
[[ -x $BIN ]] || { echo "не найден исполняемый $BIN"; exit 2; }

RUN="$(mktemp -d)"
trap 'rm -rf "$RUN"' EXIT

# ---------------------------------------------------------------------------
section "statusline: static cases (COLUMNS / glyphs / thresholds)"
# ---------------------------------------------------------------------------
# Shared session-badge fixture: a real ~/.claude/sessions snapshot recorded
# on this machine (no secrets — pid, sessionId, cwd, job names only), reused
# by every static case below via HOME, so the badge segment is identical
# between the two implementations without depending on the live machine's
# current sessions.
SL_HOME="$TESTDATA/statusline/home"

run_statusline_case() {
  local desc="$1" json_file="$2"; shift 2
  local dtmp="$RUN/sl-$$-$RANDOM"
  mkdir -p "$dtmp/old" "$dtmp/new"
  local out_old out_new
  out_old=$(env HOME="$SL_HOME" TMPDIR="$dtmp/old" "$@" bash "$OLD_STATUSLINE" < "$json_file")
  out_new=$(env HOME="$SL_HOME" TMPDIR="$dtmp/new" "$@" "$BIN" statusline < "$json_file")
  if [[ "$out_old" == "$out_new" ]]; then
    ok "$desc"
  else
    bad "$desc" "old=[$out_old] new=[$out_new]"
  fi
}

run_statusline_case "wide 120, full segments"        "$TESTDATA/statusline/stdin/case01_basic.json"          COLUMNS=120
run_statusline_case "narrow <60"                      "$TESTDATA/statusline/stdin/case02_narrow_50.json"      COLUMNS=50
run_statusline_case "narrow <80"                      "$TESTDATA/statusline/stdin/case03_narrow_70.json"      COLUMNS=70
run_statusline_case "narrow <100"                     "$TESTDATA/statusline/stdin/case04_narrow_90.json"      COLUMNS=90
run_statusline_case "ascii glyphs"                    "$TESTDATA/statusline/stdin/case05_ascii_glyphs.json"   COLUMNS=120 CLAUDE_STATUSLINE_GLYPHS=ascii
run_statusline_case "debug shows every segment"       "$TESTDATA/statusline/stdin/case06_debug_all.json"      COLUMNS=120 CLAUDE_STATUSLINE_DEBUG=1
run_statusline_case "no session_id"                   "$TESTDATA/statusline/stdin/case07_no_session.json"     COLUMNS=120
run_statusline_case "fable model - orange"            "$TESTDATA/statusline/stdin/case08_fable_model.json"    COLUMNS=120
run_statusline_case "context bar red threshold"       "$TESTDATA/statusline/stdin/case09_ctx_red.json"        COLUMNS=120
run_statusline_case "1M context window marker"        "$TESTDATA/statusline/stdin/case10_ctx_1M.json"         COLUMNS=120
run_statusline_case "five-hour window fully spent"    "$TESTDATA/statusline/stdin/case11_five_hour_over100.json" COLUMNS=120
run_statusline_case "no rate_limits object at all"    "$TESTDATA/statusline/stdin/case12_no_rate_limits.json" COLUMNS=120
run_statusline_case "TERM=dumb falls back to ascii"   "$TESTDATA/statusline/stdin/case13_term_dumb.json"      COLUMNS=120 TERM=dumb CLAUDE_STATUSLINE_GLYPHS=
run_statusline_case "non-default output style"        "$TESTDATA/statusline/stdin/case14_style_nondefault.json" COLUMNS=120
run_statusline_case "xhigh effort"                    "$TESTDATA/statusline/stdin/case15_xhigh_effort.json"   COLUMNS=120
run_statusline_case "max effort"                      "$TESTDATA/statusline/stdin/case16_max_effort.json"     COLUMNS=120
run_statusline_case "unknown effort label falls back" "$TESTDATA/statusline/stdin/case17_unknown_effort.json" COLUMNS=120
run_statusline_case "custom agent suffix"             "$TESTDATA/statusline/stdin/case18_custom_agent.json"   COLUMNS=120
printf '{}' > "$RUN/empty_payload.json"
run_statusline_case "empty payload {}"                "$RUN/empty_payload.json"                               COLUMNS=120

# ---------------------------------------------------------------------------
section "statusline: rate-limit history (time-relative — templated, not frozen)"
# ---------------------------------------------------------------------------
# These three depend on "now": a frozen absolute epoch would drift out of
# every window as real time passes, so the fixture is a template with
# __NOW_M<seconds>__ / __RESET__ placeholders, substituted with the actual
# run's clock right before use. That is the one thing about this test class
# that cannot be a byte-frozen file — see the report's self-check.
render_template() {
  local src="$1" dst="$2" now="$3" reset="$4"
  sed -e "s/__RESET__/$reset/g" \
      -e "s/__NOW_M1800__/$((now - 1800))/g" \
      -e "s/__NOW_M1500__/$((now - 1500))/g" \
      -e "s/__NOW_M1200__/$((now - 1200))/g" \
      -e "s/__NOW_M900__/$((now - 900))/g" \
      -e "s/__NOW_M600__/$((now - 600))/g" \
      -e "s/__NOW_M300__/$((now - 300))/g" \
      "$src" > "$dst"
}

run_statusline_history_case() {
  local desc="$1" json_tmpl="$2" state_dir="$3"; shift 3
  local now reset dtmp
  now=$(date +%s)
  reset=$((now + 3000))
  dtmp="$RUN/slh-$$-$RANDOM"
  mkdir -p "$dtmp/old/claude-limit" "$dtmp/new/claude-limit" "$dtmp/json"
  render_template "$json_tmpl" "$dtmp/json/in.json" "$now" "$reset"
  if [[ -d "$state_dir" ]]; then
    render_template "$state_dir/claude-limit/five_hour" "$dtmp/old/claude-limit/five_hour" "$now" "$reset"
    render_template "$state_dir/claude-limit/five_hour" "$dtmp/new/claude-limit/five_hour" "$now" "$reset"
    render_template "$state_dir/claude-limit/five_hour.window" "$dtmp/old/claude-limit/five_hour.window" "$now" "$reset"
    render_template "$state_dir/claude-limit/five_hour.window" "$dtmp/new/claude-limit/five_hour.window" "$now" "$reset"
  fi
  local out_old out_new
  out_old=$(env HOME="$SL_HOME" TMPDIR="$dtmp/old" "$@" bash "$OLD_STATUSLINE" < "$dtmp/json/in.json")
  out_new=$(env HOME="$SL_HOME" TMPDIR="$dtmp/new" "$@" "$BIN" statusline < "$dtmp/json/in.json")
  local state_old state_new
  state_old=$(cat "$dtmp/old/claude-limit/five_hour" 2>/dev/null || true)
  state_new=$(cat "$dtmp/new/claude-limit/five_hour" 2>/dev/null || true)
  if [[ "$out_old" == "$out_new" && "$state_old" == "$state_new" ]]; then
    ok "$desc"
  else
    bad "$desc" "out old=[$out_old] new=[$out_new] state-differs=$([[ "$state_old" != "$state_new" ]] && echo yes || echo no)"
  fi
}

run_statusline_history_case "accelerating 5h burn -> negative dev, trend down" \
  "$TESTDATA/statusline/stdin/case19_five_hour_accel.json" "$TESTDATA/statusline/state/case19_accel" COLUMNS=120
run_statusline_history_case "decelerating 5h burn -> trend up" \
  "$TESTDATA/statusline/stdin/case20_five_hour_decel.json" "$TESTDATA/statusline/state/case20_decel" COLUMNS=120
run_statusline_history_case "week deviation, no five-hour history" \
  "$TESTDATA/statusline/stdin/case21_week_negative_dev.json" /nonexistent COLUMNS=120

section "statusline: multi-session spend total"
dtmp="$RUN/slm-$$"
mkdir -p "$dtmp/old/claude-sessions" "$dtmp/new/claude-sessions"
cp "$TESTDATA/statusline/state/case22_multisession/claude-sessions/"* "$dtmp/old/claude-sessions/"
cp "$TESTDATA/statusline/state/case22_multisession/claude-sessions/"* "$dtmp/new/claude-sessions/"
out_old=$(env HOME="$SL_HOME" TMPDIR="$dtmp/old" COLUMNS=120 bash "$OLD_STATUSLINE" < "$TESTDATA/statusline/stdin/case22_multisession_spend.json")
out_new=$(env HOME="$SL_HOME" TMPDIR="$dtmp/new" COLUMNS=120 "$BIN" statusline < "$TESTDATA/statusline/stdin/case22_multisession_spend.json")
[[ "$out_old" == "$out_new" ]] && ok "own share / everyone's total, several session files" || bad "multisession spend" "old=[$out_old] new=[$out_new]"

# ---------------------------------------------------------------------------
section "sessions [full [session_id]]: recorded snapshot + edge cases"
# ---------------------------------------------------------------------------
run_sessions_case() {
  local desc="$1" home="$2"; shift 2
  local out_old out_new
  out_old=$(HOME="$home" python3 "$OLD_SESSIONS" "$@")
  out_new=$(HOME="$home" "$BIN" sessions "$@")
  if [[ "$out_old" == "$out_new" ]]; then
    ok "$desc"
  else
    bad "$desc" "old=[$out_old] new=[$out_new]"
  fi
}

REC_HOME="$TESTDATA/sessions/recorded"
run_sessions_case "bare mode on recorded snapshot" "$REC_HOME"
run_sessions_case "full mode on recorded snapshot" "$REC_HOME" full
run_sessions_case "full mode, self_id excludes a recorded session" "$REC_HOME" full "413069a1-4a04-442d-810d-9cc0bce44b7c"

# Edge cases need a currently-alive pid to exercise alive(): pid 1 (init /
# launchd) is alive on any Unix this runs on. A dead one is a pid unlikely
# to exist, which is fine either way — old and new observe the SAME
# process table at the SAME moment, so the comparison holds regardless of
# whether it happens to be alive.
EDGE_HOME="$RUN/sessions-edge"
mkedge() { rm -rf "$EDGE_HOME"; mkdir -p "$EDGE_HOME/.claude/sessions"; }

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}' > "$EDGE_HOME/.claude/sessions/2.json"
echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"permission prompt"}' > "$EDGE_HOME/.claude/sessions/3.json"
run_sessions_case "running+waiting+approval all present (full)" "$EDGE_HOME" full
run_sessions_case "bare mode omits running" "$EDGE_HOME"

mkedge
echo '{"kind":"bg","pid":1,"status":"idle"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "bg idle counts as waiting" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","spare":true}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "spare session excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","parkedJobId":"x"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "parked session excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"other","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "unknown kind excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":999999997,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "implausible pid treated consistently" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":"not-an-int","status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "non-integer pid excluded" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":123.0,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "float-typed pid excluded (python isinstance(int) fails)" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy"}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "no self_id arg + no sessionId field -> None==None skip" "$EDGE_HOME" full

mkedge
echo '{"kind":"interactive","pid":1,"status":"busy","sessionId":""}' > "$EDGE_HOME/.claude/sessions/1.json"
run_sessions_case "explicit empty self_id matches empty sessionId" "$EDGE_HOME" full ""

# ---------------------------------------------------------------------------
section "pane-title: shell shortcuts, container marker, node/tty lookup"
# ---------------------------------------------------------------------------
run_panetitle_case() {
  local desc="$1" pid="$2" cmd="$3" sess="$4" home="$5"; shift 5
  local out_old out_new
  out_old=$(env HOME="$home" "$@" "$OLD_PANETITLE" "$pid" "$cmd" "$sess" 2>&1)
  out_new=$(env HOME="$home" "$@" "$BIN" pane-title "$pid" "$cmd" "$sess" 2>&1)
  if [[ "$out_old" == "$out_new" ]]; then
    ok "$desc"
  else
    bad "$desc" "old=[$out_old] new=[$out_new]"
  fi
}

PT_HOME="$RUN/pt-home"
mkdir -p "$PT_HOME/.claude/sessions"
run_panetitle_case "zsh shortcut, no badge" 12345 zsh mysession "$PT_HOME"
run_panetitle_case "bash shortcut, no badge" 12345 bash mysession "$PT_HOME"
run_panetitle_case "fish shortcut, no badge" 12345 fish mysession "$PT_HOME"
run_panetitle_case "other command, no badge" 12345 nvim mysession "$PT_HOME"

echo '{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}' > "$PT_HOME/.claude/sessions/1.json"
run_panetitle_case "other command, with badge" 12345 nvim mysession "$PT_HOME"
rm -f "$PT_HOME/.claude/sessions/1.json"

# Real spawned processes exercise the actual `ps -o tty=` / `ps -t tty -o
# args=` lookup the same way for both implementations — no mocking needed,
# and both scripts see the same process table at the same instant.
python3 -c "import time; time.sleep(20)" claude-marker-parity-test &
REALPID=$!
sleep 0.3
run_panetitle_case "node cmd, real spawned process (ps tty lookup)" "$REALPID" node mysession "$PT_HOME"
kill "$REALPID" 2>/dev/null; wait "$REALPID" 2>/dev/null

sleep 20 &
REALPID2=$!
sleep 0.2
run_panetitle_case "digit-version cmd, real sleep process" "$REALPID2" 999 mysession "$PT_HOME"
kill "$REALPID2" 2>/dev/null; wait "$REALPID2" 2>/dev/null

run_panetitle_case "node cmd, nonexistent pid" 99999999 node mysession "$PT_HOME"

# ---------------------------------------------------------------------------
section "opsctx: ops-domain latch, 20+ recorded PreToolUse inputs"
# ---------------------------------------------------------------------------
run_opsctx_case() {
  local desc="$1" json_file="$2"
  local ho hn out_old out_new
  ho="$RUN/opsctx-old-$$-$RANDOM"; hn="$RUN/opsctx-new-$$-$RANDOM"
  mkdir -p "$ho" "$hn"
  out_old=$(HOME="$ho" "$OLD_OPSCTX" < "$json_file")
  out_new=$(HOME="$hn" "$BIN" opsctx < "$json_file")
  if [[ "$out_old" == "$out_new" ]]; then
    ok "$desc"
  else
    bad "$desc" "old=[$out_old] new=[$out_new]"
  fi
}

for f in "$TESTDATA"/opsctx/stdin/*.json; do
  run_opsctx_case "$(basename "$f" .json)" "$f"
done

# latch: second call in the same session+domain is silent, in both impls
ho="$RUN/opsctx-latch-old"; hn="$RUN/opsctx-latch-new"
mkdir -p "$ho" "$hn"
json="$TESTDATA/opsctx/stdin/latch_probe.json"
o1=$(HOME="$ho" "$OLD_OPSCTX" < "$json"); n1=$(HOME="$hn" "$BIN" opsctx < "$json")
o2=$(HOME="$ho" "$OLD_OPSCTX" < "$json"); n2=$(HOME="$hn" "$BIN" opsctx < "$json")
if [[ "$o1" == "$n1" && "$o2" == "$n2" && -z "$o2" ]]; then
  ok "latch: fires once per session+domain, silent on repeat"
else
  bad "latch behaviour" "1old=[$o1] 1new=[$n1] 2old=[$o2] 2new=[$n2]"
fi

# 7-day cleanup: a stale latch file (mtime 10 days back) is deleted by the
# next ops-domain call in both implementations identically.
ho="$RUN/opsctx-stale-old"; hn="$RUN/opsctx-stale-new"
mkdir -p "$ho/.claude/.state/opsctx" "$hn/.claude/.state/opsctx"
STALE_TS="$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)"
touch -t "$STALE_TS" "$ho/.claude/.state/opsctx/stale.remote" "$hn/.claude/.state/opsctx/stale.remote"
HOME="$ho" "$OLD_OPSCTX" < "$json" > /dev/null
HOME="$hn" "$BIN" opsctx < "$json" > /dev/null
old_left=$(ls "$ho/.claude/.state/opsctx" | sort | tr '\n' ',')
new_left=$(ls "$hn/.claude/.state/opsctx" | sort | tr '\n' ',')
[[ "$old_left" == "$new_left" ]] && ok "stale (>7d) latch cleaned up identically ($old_left)" || bad "stale cleanup" "old=[$old_left] new=[$new_left]"

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
