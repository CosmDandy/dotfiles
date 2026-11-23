package main

// Port of tools/claude/statusline.sh: session JSON on stdin, one line on
// stdout. Identity and context on the left, sessions and subscription limits
// on the right.
//
// The original forked jq once (still ~130ms saved over per-field forks) plus
// python for the session badge, awk for the rate-limit history and a
// handful of date/stat/readlink calls — around 30 subshells per render, on
// every statusline update and every refreshInterval tick in every live
// session. This binary decodes the same stdin JSON directly and keeps the
// rate-limit and session-cost state in memory-backed file reads, at the
// cost of re-implementing jq's default-and-floor semantics by hand — see
// the comments below wherever a Go type does not obviously match a jq
// expression.

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// --- palette -----------------------------------------------------------

const esc = "\x1b"

var (
	reset = esc + "[0m"
	// Keep terminal-adaptive hues, but make the entire footer secondary to the chat.
	green  = esc + "[2;32m"
	yellow = esc + "[2;33m"
	red    = esc + "[2;31m"
	blue   = esc + "[2;34m"
	orange = esc + "[2;38;5;9m"
	cyan   = esc + "[2;36m"
	warn   = esc + "[33m"
	danger = esc + "[1;31m"
	// Solarized's secondary foreground follows both terminal appearances in slot 11.
	gray = esc + "[2;38;5;11m"
	dim  = gray
	sep  = gray
)

// NOTE: the red threshold must equal CLAUDE_AUTOCOMPACT_PCT_OVERRIDE —
// change them as a pair, or the bar turns red only after the compact and
// warns about nothing. Yellow sits 15pp below to leave room to wrap up.
const (
	ctxYellow = 30
	ctxRed    = 45

	// The cache is shown only when it actually dips — it sits at 85-95%
	// normally, and an evergreen indicator carried no information.
	cacheShow = 80
	cacheRed  = 50

	// The 5h window is always visible: it drains in bursts (a batch of
	// workflow agents eats tens of percent in minutes), and without a
	// baseline the acceleration is noticed too late.
	fiveHourShow   = 0
	fiveHourYellow = 70
	fiveHourRed    = 90
	// NOTE: no percentage threshold on the deviation on purpose. "How much
	// is spent" and "will it last" are different questions, and tying the
	// second to the first is always late: parallel agents drive the window
	// to zero from 40%.
	devShowSec  = 3600 // more than an hour of slack — nothing to decide
	devFlatSec  = 300  // band around zero where the deviation itself drives the colour
	trendLag    = 900  // how far back the deviation is compared against for the trend
	trendMinSec = 300  // smaller shifts are noise
	weekSeconds = 7 * 24 * 3600
	weekWarnSec = 16 * 3600 // One day minus eight hours of sleep.
	// NOTE: an hour is too short an arm against a week — extrapolation
	// amplifies it x168 and any early burst draws a deviation several
	// times the truth.
	weekMinElapsed = 43200
	limitWindow    = 900 // rate averaging window, sec
	idleWindow     = 300 // silence longer than this means spending stopped
	// A 5h window cannot reset further ahead than its own length.
	fiveHourMaxAhead = 5*3600 + 600
	// Provider reset timestamps can drift by a few seconds inside the same window.
	windowResetTolerance = 60
	// An unchanged percentage is recorded at most this often: every session
	// on the machine appends to one file, and a line per tick per session
	// buys no precision the minute-scale arithmetic below can use.
	sampleEvery = 60
	// Nothing older is ever read (the trend's baseline is the oldest sample).
	historyKeep = trendLag + 2*limitWindow
)

// --- glyphs --------------------------------------------------------------

type glyphSet struct {
	think, fiveHour, week, approve, refresh, arrow string
	capL, capR                                     string
	cols                                           int
}

func pickGlyphs() glyphSet {
	mode := os.Getenv("CLAUDE_STATUSLINE_GLYPHS")
	if mode != "nerd" && mode != "ascii" {
		// NOTE: glyphs are drawn by the TERMINAL, not by the machine
		// running this — a devcontainer is entered from the same Ghostty.
		// Detection is impossible, so assume the font is there and fall
		// back only on known non-graphical TERMs.
		term := os.Getenv("TERM")
		if asciiTerm(term) {
			mode = "ascii"
		} else {
			mode = "nerd"
		}
	}
	if mode == "ascii" {
		return glyphSet{
			think: "*", fiveHour: "5h", week: "7d", approve: "", refresh: "reset", arrow: "->",
			cols: 1,
		}
	}
	// NOTE: Nerd Font icons take TWO columns in font variants without the
	// Mono suffix. Without this correction the right block overflowed and
	// Claude Code cut the tail.
	return glyphSet{
		think:    "\U000F09D1", // md-brain
		fiveHour: "\U000F0996", // md-progress_clock
		week:     "\U000F0A33", // md-calendar_week
		approve:  "\U000F033E", // md-lock — waiting for permission
		refresh:  "\U000F0450", // md-refresh
		arrow:    "⟶",
		cols:     2,
	}
}

var asciiTermRe = regexp.MustCompile(`^(dumb|linux|vt[0-9].*|ansi|cons25|sun.*)$`)

func asciiTerm(term string) bool {
	return asciiTermRe.MatchString(term)
}

func effortParts(level string) (label, color string) {
	switch level {
	case "low":
		return "low", cyan
	case "medium":
		return "medium", blue
	case "high":
		return "high", yellow
	case "xhigh":
		return "xhigh", orange
	case "max":
		return "max", red
	default:
		return strings.ToLower(level), gray
	}
}

// --- input payload ---------------------------------------------------------

type statuslinePayload struct {
	ContextWindow struct {
		UsedPercentage    *float64 `json:"used_percentage"`
		ContextWindowSize *float64 `json:"context_window_size"`
		CurrentUsage      struct {
			CacheReadInputTokens     *float64 `json:"cache_read_input_tokens"`
			InputTokens              *float64 `json:"input_tokens"`
			CacheCreationInputTokens *float64 `json:"cache_creation_input_tokens"`
		} `json:"current_usage"`
	} `json:"context_window"`
	Model struct {
		DisplayName *string `json:"display_name"`
		ID          *string `json:"id"`
	} `json:"model"`
	OutputStyle struct {
		Name *string `json:"name"`
	} `json:"output_style"`
	Effort struct {
		Level *string `json:"level"`
	} `json:"effort"`
	Thinking struct {
		Enabled *bool `json:"enabled"`
	} `json:"thinking"`
	Agent struct {
		Name *string `json:"name"`
	} `json:"agent"`
	Sessions struct {
		Running int `json:"running"`
		Waiting int `json:"waiting"`
	} `json:"sessions"`
	RateLimits struct {
		FiveHour struct {
			UsedPercentage *float64 `json:"used_percentage"`
			ResetsAt       *float64 `json:"resets_at"`
		} `json:"five_hour"`
		SevenDay struct {
			UsedPercentage *float64 `json:"used_percentage"`
			ResetsAt       *float64 `json:"resets_at"`
		} `json:"seven_day"`
	} `json:"rate_limits"`
	SessionID *string `json:"session_id"`
}

type statuslineFields struct {
	usedPct       int64
	model         string
	ctxSize       int64
	cacheRead     int64
	inputTokens   int64
	cacheCreation int64
	styleName     string
	effort        string
	thinking      string
	agent         string
	fivePct100    *int64
	fiveReset     *int64
	weekPct       *float64
	weekReset     *int64
	sid           string
	modelID       string
}

// parseFields mirrors the statusline's one jq call: a JSON field that is
// absent or null falls back to a default (0, "", "Claude", ...); one that
// is present, even as an empty string, is used as-is. That distinction is
// jq's `//` operator, not "falsy" in the usual scripting-language sense, so
// it is implemented here as "nil pointer means missing/null", not "zero
// value means missing".
func parseFields(p *statuslinePayload) statuslineFields {
	f := statuslineFields{model: "Pi", styleName: "default"}
	if p.ContextWindow.UsedPercentage != nil {
		f.usedPct = int64(math.Floor(*p.ContextWindow.UsedPercentage))
	}
	if p.Model.DisplayName != nil {
		f.model = *p.Model.DisplayName
	}
	if p.ContextWindow.ContextWindowSize != nil {
		f.ctxSize = int64(*p.ContextWindow.ContextWindowSize)
	}
	if v := p.ContextWindow.CurrentUsage.CacheReadInputTokens; v != nil {
		f.cacheRead = int64(*v)
	}
	if v := p.ContextWindow.CurrentUsage.InputTokens; v != nil {
		f.inputTokens = int64(*v)
	}
	if v := p.ContextWindow.CurrentUsage.CacheCreationInputTokens; v != nil {
		f.cacheCreation = int64(*v)
	}
	if p.OutputStyle.Name != nil {
		f.styleName = *p.OutputStyle.Name
	}
	if p.Effort.Level != nil {
		f.effort = *p.Effort.Level
	}
	if p.Thinking.Enabled != nil && *p.Thinking.Enabled {
		f.thinking = "1"
	}
	if p.Agent.Name != nil {
		f.agent = *p.Agent.Name
	}
	if v := p.RateLimits.FiveHour.UsedPercentage; v != nil {
		n := int64(math.Floor(*v * 100))
		f.fivePct100 = &n
	}
	if v := p.RateLimits.FiveHour.ResetsAt; v != nil {
		n := int64(*v)
		f.fiveReset = &n
	}
	f.weekPct = p.RateLimits.SevenDay.UsedPercentage
	if v := p.RateLimits.SevenDay.ResetsAt; v != nil {
		n := int64(*v)
		f.weekReset = &n
	}
	if p.SessionID != nil {
		f.sid = *p.SessionID
	}
	if p.Model.ID != nil {
		f.modelID = *p.Model.ID
	}
	return f
}

// --- limits ----------------------------------------------------------------

// fmtClock mirrors fmt_clock(): minutes are mandatory since this is a
// deadline, and truncating to the hour lies by almost an hour, always in
// the direction of "less time than you have".
func fmtClock(ts int64) string {
	t := time.Unix(ts, 0)
	return fmt.Sprintf("%d:%02d", t.Hour(), t.Minute())
}

// fmtDev renders a signed deviation: "+40m" is slack left at reset, "-12m"
// is how much earlier it runs out.
func fmtDev(s int64) string {
	sign := "+"
	if s < 0 {
		sign = "-"
		s = -s
	}
	// Under a minute either way is "just barely", not "minus zero".
	if s < 60 {
		return "0м"
	}
	if s >= 3600 {
		return fmt.Sprintf("%s%dч%02dм", sign, s/3600, (s%3600)/60)
	}
	return fmt.Sprintf("%s%dм", sign, s/60)
}

func usageColor(pct, yellowAt, redAt int64) string {
	switch {
	case pct >= redAt:
		return danger
	case pct >= yellowAt:
		return warn
	default:
		return green
	}
}

func fmtHoursRemaining(seconds int64) string {
	if seconds < 3600 {
		return "<1ч"
	}
	return fmt.Sprintf("%dч", seconds/3600)
}

type fiveHourResult struct {
	pct100 int64
	reset  *int64
	dev    *int64
	trend  string
}

// awkSample is one "timestamp pct100" line from the five_hour history file.
type awkSample struct {
	ts, pct int64
}

// fiveHourDev ports five_hour_dev(): will the current rate last until the
// 5h window resets. Percentages are kept in hundredths, and the sample file
// is shared across sessions — the limit is per-account, not per-session.
func fiveHourDev(pct100 int64, reset *int64, now int64) fiveHourResult {
	// NOTE: Claude Code has sent resets_at = 2030-01-01 right after a window
	// reset. Taken at face value it became the window marker below, every
	// real payload after it looked stale, and the segment froze on
	// "0% (3:00)" until the marker file was deleted by hand.
	if reset != nil && *reset > now+fiveHourMaxAhead {
		reset = nil
	}
	tmpdir := os.Getenv("TMPDIR")
	if tmpdir == "" {
		tmpdir = "/tmp"
	}
	dir := filepath.Join(tmpdir, "claude-limit")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fiveHourResult{pct100: pct100, reset: reset}
	}
	f := filepath.Join(dir, "five_hour")
	if reset == nil {
		return fiveHourResult{pct100: pct100, reset: reset}
	}

	// A new window moves the reset materially forward; second-scale jitter is not a rollover.
	wf := f + ".window"
	var prevReset int64
	if data, err := os.ReadFile(wf); err == nil {
		fmt.Sscanf(strings.TrimSpace(string(data)), "%d", &prevReset)
	}
	if prevReset > now+fiveHourMaxAhead { // a marker written before the check above
		prevReset = 0
	}
	if prevReset <= now || *reset > prevReset+windowResetTolerance {
		_ = os.WriteFile(wf, []byte(fmt.Sprintf("%d\n", *reset)), 0o644)
		_ = os.WriteFile(f, []byte(fmt.Sprintf("%d %d\n", now, pct100)), 0o644) // new window — new baseline
		return fiveHourResult{pct100: pct100, reset: reset}
	}

	var last, lastTS int64
	if data, err := os.ReadFile(f); err == nil {
		lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
		if lastLine := lines[len(lines)-1]; lastLine != "" {
			fields := strings.Fields(lastLine)
			if len(fields) >= 2 {
				lastTS, _ = strconv.ParseInt(fields[0], 10, 64)
				last, _ = strconv.ParseInt(fields[1], 10, 64)
			}
		}
	}

	// History may inform a forecast, but must never replace the provider's current percentage.
	if *reset < prevReset-windowResetTolerance {
		return fiveHourResult{pct100: pct100, reset: reset}
	}
	if pct100 < last {
		_ = os.WriteFile(f, []byte(fmt.Sprintf("%d %d\n", now, pct100)), 0o644)
		return fiveHourResult{pct100: pct100, reset: reset}
	}
	switch {
	case pct100 == last && now-lastTS < sampleEvery:
	default:
		// NOTE: append only. Rewriting the file through `awk > tmp && mv`
		// on every tick let parallel sessions overwrite each other, so the
		// history lived seconds and never reached span >= 60. A short
		// append is atomic; the window is selected on READ.
		appendLine(f, fmt.Sprintf("%d %d\n", now, pct100))
	}

	samples := readSamples(f)
	// Baseline: the last sample older than the window, else the earliest
	// inside it. idlePct is the percentage at the IDLE_WINDOW boundary;
	// the pb/pl pair is the same window shifted TREND_LAG back, which is
	// what the trend arrow compares against.
	var bTS, bPct, fTS, fPct, iPct, lTS, lPct *int64
	var pbTS, pbPct, pfTS, pfPct, plTS, plPct *int64
	for _, s := range samples {
		ts, pct := s.ts, s.pct
		if ts < now-limitWindow {
			if ts >= now-2*limitWindow {
				bTS, bPct = &ts, &pct
			}
		} else {
			if fTS == nil {
				fTS, fPct = &ts, &pct
			}
			if ts < now-idleWindow {
				iPct = &pct
			}
			lTS, lPct = &ts, &pct
		}
		if ts < now-trendLag-limitWindow {
			if ts >= now-trendLag-2*limitWindow {
				pbTS, pbPct = &ts, &pct
			}
		} else if ts <= now-trendLag {
			if pfTS == nil {
				pfTS, pfPct = &ts, &pct
			}
			plTS, plPct = &ts, &pct
		}
	}
	if bTS == nil {
		bTS, bPct = fTS, fPct
	}
	if iPct == nil {
		iPct = bPct
	}
	if pbTS == nil {
		pbTS, pbPct = pfTS, pfPct
	}
	if bTS == nil || lTS == nil {
		return fiveHourResult{pct100: pct100, reset: reset}
	}
	if pbTS == nil || plTS == nil {
		zero := int64(0)
		pbTS, pbPct, plTS, plPct = &zero, &zero, &zero, &zero
	}

	// Keep the file bounded by age, not by count: a count cut left minutes of
	// history when several sessions appended, and the trend needs 45.
	// Rare enough (~200 minutes of samples) that a race does not matter.
	if len(samples) > 200 {
		var b strings.Builder
		for _, s := range samples {
			if s.ts >= now-historyKeep {
				fmt.Fprintf(&b, "%d %d\n", s.ts, s.pct)
			}
		}
		_ = os.WriteFile(f, []byte(b.String()), 0o644)
	}

	// NOTE: the percentage arrives in whole points, so on a short arm a
	// one-step delta changes the rate several-fold and the forecast
	// flickers. Both time and a visible change are required: 180 seconds
	// and one whole point.
	span := *lTS - *bTS
	delta := *lPct - *bPct

	var dev *int64
	trend := ""
	// NOTE: idle detection — the sliding window does not notice a stop by
	// itself, it keeps dividing an old burst by the full arm and reporting
	// a brisk rate.
	if *lPct-*iPct > 0 && span >= 180 && delta >= 100 {
		// How long the remainder lasts MINUS the wait for the reset.
		// NOTE: the rate is deliberately not computed as its own value —
		// rounding hundredths of a percent per minute ate up to 4% and
		// swung the deviation by seven minutes between ticks. One
		// division for the whole expression, no intermediate loss.
		d := (10000-pct100)*span/delta - (*reset - now)
		dev = &d

		// NOTE: the trend compares the deviation with itself TREND_LAG
		// ago. Against "five minutes ago" a whole-point step gives either
		// zero or a jump, and the colour twitches.
		pspan := *plTS - *pbTS
		if *pbTS > 0 && pspan >= 180 && *plPct-*pbPct >= 100 {
			pdev := (10000-*plPct)*pspan/(*plPct-*pbPct) - (*reset - now + trendLag)
			switch {
			case d-pdev > trendMinSec:
				trend = "up"
			case pdev-d > trendMinSec:
				trend = "down"
			default:
				trend = "flat"
			}
		}
	}

	return fiveHourResult{pct100: pct100, reset: reset, dev: dev, trend: trend}
}

func appendLine(path, line string) {
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
}

func readSamples(path string) []awkSample {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []awkSample
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		ts, err1 := strconv.ParseInt(fields[0], 10, 64)
		pct, err2 := strconv.ParseInt(fields[1], 10, 64)
		if err1 != nil || err2 != nil {
			continue
		}
		out = append(out, awkSample{ts: ts, pct: pct})
	}
	return out
}

// Percentages come from the provider payload; local history only estimates the forecast.
func computeLimits(g glyphSet, now int64, wantETA bool, fields statuslineFields, debugAll bool) string {
	fiveSeg := ""
	if fields.fivePct100 != nil {
		res := fiveHourDev(*fields.fivePct100, fields.fiveReset, now)
		fivePct := res.pct100 / 100
		if fivePct >= fiveHourShow || debugAll {
			// NOTE: the forecast colour follows the TREND, not the position — the
			// sign is already in the number. That gives two independent
			// measurements in one segment: "-12m" in red is "not going to
			// make it and accelerating", in green "not going to make it
			// but already slowing". With no trend yet the colour falls
			// back to the sign.
			color := dim
			switch res.trend {
			case "up":
				color = green
			case "down":
				color = red
			case "flat":
				color = cyan
			default:
				if res.dev != nil {
					switch {
					case *res.dev > devFlatSec:
						color = green
					case *res.dev < -devFlatSec:
						color = red
					default:
						color = cyan
					}
				}
			}
			if fivePct >= 100 {
				// Window fully spent: only the release time still matters.
				fiveSeg = danger + g.refresh
				if res.reset != nil {
					fiveSeg += " " + fmtClock(*res.reset)
				}
				fiveSeg += reset
			} else {
				// NOTE: the arrow is added only for a negative deviation.
				// reset+dev is then the moment we hit 0% BEFORE the real
				// reset; with a positive dev it would land after the
				// reset, i.e. describe a window that opens before it is
				// exhausted.
				fiveSeg = usageColor(fivePct, fiveHourYellow, fiveHourRed) + g.fiveHour + " " + strconv.FormatInt(fivePct, 10) + "%" + reset + color
				var eta *int64
				if res.dev != nil && *res.dev < devShowSec && wantETA {
					fiveSeg += " " + fmtDev(*res.dev)
					if res.reset != nil && *res.dev < 0 {
						e := *res.reset + *res.dev
						eta = &e
					}
				}
				if res.reset != nil {
					if eta != nil {
						fiveSeg += " (" + fmtClock(*res.reset) + " " + g.arrow + " " + fmtClock(*eta) + ")"
					} else {
						fiveSeg += " (" + fmtClock(*res.reset) + ")"
					}
				}
				fiveSeg += reset
			}
		}
	}

	weekSeg := ""
	if fields.weekPct != nil {
		used := *fields.weekPct
		color, forecast := dim, ""
		if fields.weekReset != nil {
			untilReset := *fields.weekReset - now
			elapsed := weekSeconds - untilReset
			if elapsed >= 0 && untilReset > 0 {
				// Convert overspend against the linear budget into hours of that budget.
				over := used*weekSeconds/100 - float64(elapsed)
				if over > 0 {
					color = warn
					if over > weekWarnSec {
						color = danger
					}
					forecast = " " + fmtDev(-int64(over))
					if elapsed >= weekMinElapsed && used < 100 {
						untilEmpty := float64(elapsed) * (100 - used) / used
						// Show the countdown only as the projected early exhaustion approaches.
						if 2*untilEmpty <= float64(untilReset) {
							forecast += " " + g.arrow + " " + fmtHoursRemaining(int64(untilEmpty))
						}
					}
				}
			}
		}
		weekSeg = color + g.week + " " + strconv.FormatInt(int64(used), 10) + "%" + forecast + reset
	}

	segs := fiveSeg
	if weekSeg != "" {
		if segs != "" {
			segs = segs + " " + sep + "·" + reset + " " + weekSeg
		} else {
			segs = weekSeg
		}
	}
	return segs
}

// --- alignment ---------------------------------------------------------

var ansiRe = regexp.MustCompile(esc + `\[[0-9;]*m`)

// visWidth is the visible width: ANSI sequences take no space and a rune
// count undercounts a Nerd Font icon, which is one codepoint over
// glyphCols columns — the undercount accumulated and pushed the right
// block off the edge.
func visWidth(s string, g glyphSet) int {
	stripped := ansiRe.ReplaceAllString(s, "")
	n := len([]rune(stripped))
	if g.cols > 1 {
		for _, gl := range []string{g.think, g.fiveHour, g.week, g.approve, g.refresh} {
			if gl == "" {
				continue
			}
			n += strings.Count(stripped, gl) * (g.cols - 1)
		}
	}
	return n
}

// Keep limits visible on narrow terminals instead of clipping the right block.
func joinEdges(left, right string, cols, rightMargin int, g glyphSet) string {
	if right == "" {
		return left
	}
	gap := cols - rightMargin - visWidth(left, g) - visWidth(right, g)
	if gap < 2 {
		return left + "\n" + right
	}
	return left + strings.Repeat(" ", gap) + right
}

func add(acc, segAdd string) string {
	if segAdd == "" {
		return acc
	}
	if acc == "" {
		return segAdd
	}
	return acc + " " + sep + "·" + reset + " " + segAdd
}

// --- entry point -----------------------------------------------------------

func runStatusline(_ []string) {
	raw, err := io.ReadAll(os.Stdin)
	if err != nil {
		return
	}
	var p statuslinePayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return
	}
	fields := parseFields(&p)

	g := pickGlyphs()
	debugAll := os.Getenv("CLAUDE_STATUSLINE_DEBUG") != ""

	cols := 100
	if v := os.Getenv("COLUMNS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			cols = n
		}
	}
	margin := 0

	now := time.Now().Unix()
	// CLAUDE_CLI_NOW is a test-only override: the rate-limit history fixtures
	// sit their sample offsets exactly on the window/trend-lag boundaries, so
	// any drift between the shell's `now` and this process's own clock read
	// can flip which side of a boundary a sample falls on. Pinning "now" to
	// the same value the fixture was rendered with removes that race.
	if v := os.Getenv("CLAUDE_CLI_NOW"); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			now = n
		}
	}

	// --- model block -------------------------------------------------
	// Model [1M] [· effort] [▸ custom agent].
	// NOTE: the 1M fact comes from context_window_size, not from the
	// display name — that one reads "Opus 5 (1M context)" today and is
	// Anthropic's to rename.
	modelStr := fields.model
	if i := strings.Index(modelStr, " ("); i >= 0 {
		modelStr = modelStr[:i]
	}
	// Fable costs several times what the others do; orange marks the name.
	// Matched on the id and on the display name both:
	// Anthropic renames one or the other, not both at once.
	modelColour := gray
	if fableRe.MatchString(fields.modelID + " " + fields.model) {
		modelColour = orange
	}
	ctxMark := ""
	if fields.ctxSize >= 1000000 {
		ctxMark = sep + " 1M" + reset
	}
	modelSeg := modelColour + modelStr + reset + ctxMark
	if fields.effort != "" {
		label, color := effortParts(fields.effort)
		modelSeg += sep + " · " + reset + color + label + reset
	}
	// the base agent is called "claude" — not information, so only custom
	// ones are shown
	switch fields.agent {
	case "", "claude", "Claude":
	default:
		modelSeg += gray + " ▸ " + fields.agent + reset
	}

	// --- context -------------------------------------------------------
	ctxColor := usageColor(fields.usedPct, ctxYellow, ctxRed)
	ctxSeg := ctxColor + strconv.FormatInt(fields.usedPct, 10) + "%" + reset

	// --- cache ----------------------------------------------------------
	// only when it dipped, and only when there is something to divide
	// (current_usage is empty at session start and right after /compact).
	cacheSeg := ""
	totalInput := fields.cacheRead + fields.inputTokens + fields.cacheCreation
	if totalInput > 0 {
		cacheHit := fields.cacheRead * 100 / totalInput
		if cacheHit < cacheShow || debugAll {
			cacheColor := yellow
			if cacheHit < cacheRed {
				cacheColor = red
			}
			if cacheHit >= cacheShow {
				cacheColor = green
			}
			cacheSeg = cacheColor + "◎ " + strconv.FormatInt(cacheHit, 10) + "%" + reset
		}
	}

	badgeSeg := ""
	if p.Sessions.Running > 0 {
		badgeSeg = cyan + "◉ " + strconv.Itoa(p.Sessions.Running) + reset
	}
	if p.Sessions.Waiting > 0 {
		if badgeSeg != "" {
			badgeSeg += " "
		}
		badgeSeg += yellow + "○ " + strconv.Itoa(p.Sessions.Waiting) + reset
	}

	styleSeg := ""
	if fields.styleName != "default" {
		styleSeg = gray + "⊙ " + fields.styleName + reset
	}

	// --- render ----------------------------------------------------------
	limits := computeLimits(g, now, cols >= 100, fields, debugAll)
	left := add(modelSeg, ctxSeg)
	right := badgeSeg
	if cols >= 100 {
		left = add(left, styleSeg)
		right = add(cacheSeg, right)
	}
	right = add(right, limits)
	fmt.Print(joinEdges(left, right, cols, margin, g))
}

var fableRe = regexp.MustCompile(`[Ff]able`)
