package main

// Port of tools/claude/statusline.sh: session JSON on stdin, one line on
// stdout. Identity and context on the left, spend and subscription limits
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
	"os/exec"
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
	// Palette slots 0-15 only, so the line follows the terminal theme
	// instead of hardcoded shades.
	green  = esc + "[32m"
	yellow = esc + "[33m"
	red    = esc + "[31m"
	blue   = esc + "[34m"
	// Solarized orange DOES have a slot: it lands on 9, the one named "bright
	// red", and the ghostty iTerm2 presets put #cb4b16 there in both the light
	// and the dark variant. So this follows the theme like everything else;
	// 166 was an absolute xterm tone that did not. Contrast holds on both
	// sides: 3.26 dark, 4.27 light. It exists for a single purpose: the Fable
	// segments.
	orange = esc + "[38;5;9m"
	// Neutral for "on track" — green already means "room to accelerate" in
	// these segments.
	cyan = esc + "[36m"
	// NOTE: secondary text is ANSI 11, not "bright black" (8) or faint.
	// Solarized defines the secondary tone with different codes for its
	// light and dark themes, and the theme switches automatically here; 8
	// gives a contrast of ~2.1 on dark against a readability floor of 3.
	// Only 11 stays above it on both sides (3.37 dark / 4.13 light).
	gray = esc + "[38;5;11m"
	// 38;5;11 is not "bright yellow" here: under Solarized it is base00,
	// the body text colour, and the theme follows the system — light by
	// day, dark by night. So the shade stays, and what recedes is the
	// WEIGHT: SGR 2 (faint) dims relative to whatever the foreground
	// currently is, which survives both themes where an absolute grey
	// cannot (238 sinks on dark, turns near-black on light — tried, wrong
	// both ways).
	dim = esc + "[38;5;11m"
	sep = esc + "[2;38;5;11m"
)

// NOTE: the red threshold must equal CLAUDE_AUTOCOMPACT_PCT_OVERRIDE —
// change them as a pair, or the bar turns red only after the compact and
// warns about nothing. Yellow sits 15pp below to leave room to wrap up.
const (
	ctxYellow = 30
	ctxRed    = 45
	barLen    = 10

	// The cache is shown only when it actually dips — it sits at 85-95%
	// normally, and an evergreen indicator carried no information.
	cacheShow = 80
	cacheRed  = 50

	// The 5h window is always visible: it drains in bursts (a batch of
	// workflow agents eats tens of percent in minutes), and without a
	// baseline the acceleration is noticed too late.
	fiveHourShow = 0
	// NOTE: no percentage threshold on the deviation on purpose. "How much
	// is spent" and "will it last" are different questions, and tying the
	// second to the first is always late: parallel agents drive the window
	// to zero from 40%.
	devShowSec  = 3600 // more than an hour of slack — nothing to decide
	devFlatSec  = 300  // band around zero where the deviation itself drives the colour
	trendLag    = 900  // how far back the deviation is compared against for the trend
	trendMinSec = 300  // smaller shifts are noise
	// The week is a budget, the 5h window only a speed limit — so the goal
	// here is to sit at zero, and an underspend is as much a signal as an
	// overspend.
	weekSeconds = 604800
	weekFlatSec = 43200 // ±half a day counts as on schedule
	// NOTE: an hour is too short an arm against a week — extrapolation
	// amplifies it x168 and any early burst draws a deviation several
	// times the truth.
	weekMinElapsed = 43200
	limitWindow    = 900 // rate averaging window, sec
	idleWindow     = 300 // silence longer than this means spending stopped

	sessionTTL = 90
)

// --- glyphs --------------------------------------------------------------

type glyphSet struct {
	think, fiveHour, week, approve, dead, arrow string
	capL, capR                                  string
	cols                                        int
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
			think: "*", fiveHour: "5h", week: "7d", approve: "", dead: "!!", arrow: "->",
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
		dead:     "\U0001F480", // window fully spent
		arrow:    "⟶",
		cols:     2,
	}
}

var asciiTermRe = regexp.MustCompile(`^(dumb|linux|vt[0-9].*|ansi|cons25|sun.*)$`)

func asciiTerm(term string) bool {
	return asciiTermRe.MatchString(term)
}

// Effort marks exactly as Claude Code's own /effort menu shows them. Plain
// Unicode, one column, so they are outside the width correction above.
// NOTE: ultracode (✦) does not arrive as its own level — it reports as
// xhigh.
func effortParts(level string) (glyph, label, color string) {
	switch level {
	case "low":
		return "○", "Low", gray
	case "medium":
		return "◐", "Medium", gray
	case "high":
		return "●", "High", gray
	case "xhigh":
		return "◉", "xHigh", yellow
	case "max":
		return "◈", "Max", red
	default:
		return "", level, gray
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
	Cost struct {
		TotalCostUSD *float64 `json:"total_cost_usd"`
	} `json:"cost"`
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
	costCents     int64
	fivePct100    *int64
	fiveReset     *int64
	weekPct       *int64
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
	f := statuslineFields{model: "Claude", styleName: "default"}
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
	if p.Cost.TotalCostUSD != nil {
		f.costCents = int64(math.Floor(*p.Cost.TotalCostUSD * 100))
	}
	if v := p.RateLimits.FiveHour.UsedPercentage; v != nil {
		n := int64(math.Floor(*v * 100))
		f.fivePct100 = &n
	}
	if v := p.RateLimits.FiveHour.ResetsAt; v != nil {
		n := int64(*v)
		f.fiveReset = &n
	}
	if v := p.RateLimits.SevenDay.UsedPercentage; v != nil {
		n := int64(math.Floor(*v))
		f.weekPct = &n
	}
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

// --- context bar -----------------------------------------------------------

var eighths = [8]string{" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}

// renderBar draws the block bar in theme colours; the last occupied cell is
// filled with an eighth block, giving 1/8-cell precision at the same width.
// NOTE: the CAP_L/CAP_R wrapping branch of the shell version is dead code —
// both glyph modes set them empty — and is not ported.
func renderBar(pct, length int64) string {
	e := pct * length * 8 / 100
	full := e / 8
	frac := e % 8
	gCells := ctxYellow * length / 100
	yCells := ctxRed * length / 100

	var out strings.Builder
	for i := int64(0); i < length; i++ {
		c := red
		if i < gCells {
			c = green
		} else if i < yCells {
			c = yellow
		}
		out.WriteString(c)
		switch {
		case i < full:
			out.WriteString("█")
		case i == full && frac > 0:
			out.WriteString(eighths[frac])
		default:
			out.WriteString("░")
		}
	}
	out.WriteString(reset)
	return out.String()
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

// fmtDevDays is the same for the weekly window, in days. The tenth matters:
// whole days are too coarse on a week-long arm and hours are unreadable.
func fmtDevDays(s int64) string {
	sign := "+"
	if s < 0 {
		sign = "-"
		s = -s
	}
	t := s * 10 / 86400
	if t == 0 {
		return "0.0д"
	}
	return fmt.Sprintf("%s%d.%dд", sign, t/10, t%10)
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

	// NOTE: window rollover is detected by resets_at, NOT by the
	// percentage dropping. Sessions update the payload at their own pace
	// and an idle one holds a snapshot for hours, so any drop threshold
	// fires spuriously and wipes the history. resets_at changes exactly at
	// the reset and only forward.
	wf := f + ".window"
	var prevReset int64
	if data, err := os.ReadFile(wf); err == nil {
		fmt.Sscanf(strings.TrimSpace(string(data)), "%d", &prevReset)
	}
	if *reset > prevReset {
		_ = os.WriteFile(wf, []byte(fmt.Sprintf("%d\n", *reset)), 0o644)
		_ = os.WriteFile(f, []byte(fmt.Sprintf("%d %d\n", now, pct100)), 0o644) // new window — new baseline
		return fiveHourResult{pct100: pct100, reset: reset}
	}

	var last int64
	if data, err := os.ReadFile(f); err == nil {
		lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
		if lastLine := lines[len(lines)-1]; lastLine != "" {
			fields := strings.Fields(lastLine)
			if len(fields) >= 2 {
				last, _ = strconv.ParseInt(fields[1], 10, 64)
			}
		}
	}

	// NOTE: a stale snapshot is not written to history but the calculation
	// continues — the limit is per-account, so an idle session must show
	// the same picture as an active one. An early return here used to
	// leave lagging windows with no forecast at all.
	switch {
	case *reset < prevReset:
		r := prevReset
		reset = &r
		pct100 = last
	case pct100 < last:
		pct100 = last
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

	// keep the file bounded; rare enough that a race does not matter
	if len(samples) > 600 {
		tail := samples[len(samples)-100:]
		var b strings.Builder
		for _, s := range tail {
			fmt.Fprintf(&b, "%d %d\n", s.ts, s.pct)
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

// computeLimits ports compute_limits(): subscription limits straight from
// the payload — no network, no cache, and it works unchanged in a
// devcontainer.
func computeLimits(g glyphSet, now int64, wantETA, wantWeek bool, fields statuslineFields, debugAll bool) string {
	fiveSeg := ""
	if fields.fivePct100 != nil {
		res := fiveHourDev(*fields.fivePct100, fields.fiveReset, now)
		fivePct := res.pct100 / 100
		if fivePct >= fiveHourShow || debugAll {
			// NOTE: the colour follows the TREND, not the position — the
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
				fiveSeg = red + g.dead + " you lose"
				if res.reset != nil {
					fiveSeg += " (" + fmtClock(*res.reset) + ")"
				}
				fiveSeg += reset
			} else {
				// NOTE: the arrow is added only for a negative deviation.
				// reset+dev is then the moment we hit 0% BEFORE the real
				// reset; with a positive dev it would land after the
				// reset, i.e. describe a window that opens before it is
				// exhausted.
				fiveSeg = color + g.fiveHour + " " + strconv.FormatInt(fivePct, 10) + "%"
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
	if fields.weekPct != nil && wantWeek {
		// NOTE: the weekly deviation is a comparison against a LINEAR
		// schedule, not an extrapolated rate — dividing by the percentage
		// produced +53d and -3.8d out of nowhere on a small percentage or
		// a short arm. Only a shortfall is shown: the goal is to consume
		// the subscription, so a surplus interests nobody.
		color := dim
		var weekDev *int64
		if fields.weekReset != nil {
			elapsed := weekSeconds - (*fields.weekReset - now)
			if elapsed >= weekMinElapsed {
				d := elapsed - *fields.weekPct*weekSeconds/100
				if d < 0 {
					weekDev = &d
					if d < -weekFlatSec {
						color = red
					}
				}
			}
		}
		weekSeg = color + g.week + " " + strconv.FormatInt(*fields.weekPct, 10) + "%"
		if weekDev != nil {
			weekSeg += " " + fmtDevDays(*weekDev)
		}
		weekSeg += reset
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
		for _, gl := range []string{g.think, g.fiveHour, g.week, g.approve, g.dead} {
			if gl == "" {
				continue
			}
			n += strings.Count(stripped, gl) * (g.cols - 1)
		}
	}
	return n
}

// joinEdges hugs the right block to the terminal edge; when the line is too
// short both halves are joined into one ribbon, which beats wrapping onto a
// second line.
func joinEdges(left, right string, cols, rightMargin int, g glyphSet) string {
	if right == "" {
		return left
	}
	gap := cols - rightMargin - visWidth(left, g) - visWidth(right, g)
	if gap < 2 {
		return left + " " + sep + "·" + reset + " " + right
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

// --- right margin ------------------------------------------------------

// rightMargin mirrors the Remote Control chip probe: whether THIS session
// holds a bridge is answered by ~/.claude.json's replBridgePlaceholders,
// each carrying the pid that owns it. Walk up from this process to the
// owning `claude` process and see whether its pid is among them.
func rightMargin(pid int) int {
	if v, ok := os.LookupEnv("CLAUDE_STATUSLINE_MARGIN"); ok {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}

	rc := 2
	home, err := os.UserHomeDir()
	if err != nil {
		return rc
	}
	data, err := os.ReadFile(filepath.Join(home, ".claude.json"))
	if err != nil {
		return rc
	}
	dec := json.NewDecoder(strings.NewReader(string(data)))
	dec.UseNumber()
	var parsed map[string]any
	if dec.Decode(&parsed) != nil {
		return rc
	}
	placeholders, _ := parsed["replBridgePlaceholders"].(map[string]any)
	var bridgePIDs []string
	for _, v := range placeholders {
		entry, ok := v.(map[string]any)
		if !ok {
			continue
		}
		pidVal, ok := entry["pid"]
		if !ok || pidVal == nil {
			continue
		}
		if n, ok := pidVal.(json.Number); ok {
			bridgePIDs = append(bridgePIDs, n.String())
		}
	}
	if len(bridgePIDs) == 0 {
		return rc
	}

	probe := pid
	for hops := 0; hops < 6 && probe > 1; hops++ {
		matched := false
		for _, bp := range bridgePIDs {
			if bp == strconv.Itoa(probe) {
				matched = true
				break
			}
		}
		if matched {
			return 5
		}
		probe = parentPID(probe)
	}
	return rc
}

func parentPID(pid int) int {
	out, err := exec.Command("ps", "-o", "ppid=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(out)))
	if err != nil {
		return 0
	}
	return n
}

// --- money ---------------------------------------------------------------

// fmtMoney renders whole dollars: cents cost four columns and decide
// nothing. Rounded, not truncated, so a session at 90 cents reads $1
// rather than $0.
func fmtMoney(cents int64) string {
	return fmt.Sprintf("$%d", (cents+50)/100)
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
	margin := rightMargin(os.Getpid())

	now := time.Now().Unix()

	// --- model block -------------------------------------------------
	// [brain] Model [1M] [· effort] [▸ custom agent].
	// NOTE: the 1M fact comes from context_window_size, not from the
	// display name — that one reads "Opus 5 (1M context)" today and is
	// Anthropic's to rename.
	modelStr := fields.model
	if i := strings.Index(modelStr, " ("); i >= 0 {
		modelStr = modelStr[:i]
	}
	// Fable costs several times what the others do, and the name alone
	// does not say so after a week of reading it. Orange on the name and
	// on the spend below — the two places that say this session is the
	// expensive kind. Matched on the id and on the display name both:
	// Anthropic renames one or the other, not both at once.
	modelColour := blue
	fable := false
	if fableRe.MatchString(fields.modelID + " " + fields.model) {
		modelColour = orange
		fable = true
	}
	ctxMark := ""
	if fields.ctxSize >= 1000000 {
		ctxMark = sep + " 1M" + reset
	}
	modelSeg := modelColour + modelStr + reset + ctxMark
	if fields.thinking != "" {
		modelSeg = modelColour + g.think + " " + modelStr + reset + ctxMark
	}
	modelSegSlim := modelSeg
	if fields.effort != "" {
		glyph, label, color := effortParts(fields.effort)
		if glyph != "" {
			modelSeg += sep + " · " + reset + color + glyph + " " + label + reset
		} else {
			modelSeg += sep + " · " + reset + label + reset
		}
	}
	// the base agent is called "claude" — not information, so only custom
	// ones are shown
	switch fields.agent {
	case "", "claude", "Claude":
	default:
		modelSeg += gray + " ▸ " + fields.agent + reset
		modelSegSlim += gray + " ▸ " + fields.agent + reset
	}

	// --- context -------------------------------------------------------
	ctxColor := green
	if fields.usedPct >= ctxYellow {
		ctxColor = yellow
	}
	if fields.usedPct >= ctxRed {
		ctxColor = red
	}
	bar := renderBar(fields.usedPct, barLen)
	ctxSeg := bar + " " + ctxColor + strconv.FormatInt(fields.usedPct, 10) + "%" + reset

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

	// --- money and sessions -------------------------------------------
	// how many of us, my share, everyone's total. NOTE: the 5h/7d limits
	// are per-account but the cost in the payload is per-session, so with
	// several windows open only one share is visible. Each session writes
	// its own file; alive means touched within sessionTTL.
	total := int64(0)
	if fields.sid != "" {
		tmpdir := os.Getenv("TMPDIR")
		if tmpdir == "" {
			tmpdir = "/tmp"
		}
		sdir := filepath.Join(tmpdir, "claude-sessions")
		if err := os.MkdirAll(sdir, 0o755); err == nil {
			_ = os.WriteFile(filepath.Join(sdir, fields.sid), []byte(fmt.Sprintf("%d\n", fields.costCents)), 0o644)
			entries, _ := os.ReadDir(sdir)
			for _, e := range entries {
				if e.IsDir() {
					continue
				}
				path := filepath.Join(sdir, e.Name())
				info, err := os.Stat(path)
				if err != nil {
					continue
				}
				if now-info.ModTime().Unix() > sessionTTL {
					_ = os.Remove(path) // session closed or long silent
					continue
				}
				data, err := os.ReadFile(path)
				c := int64(0)
				if err == nil {
					fmt.Sscanf(strings.TrimSpace(string(data)), "%d", &c)
				}
				total += c
			}
		}
	}

	// What the other sessions are doing, not how many exist: running,
	// waiting for an answer, waiting for permission. Read from
	// ~/.claude/sessions/*.json.
	sidPtr := &fields.sid
	claudeBadge := sessionBadge(true, sidPtr)

	money := sep
	if fable {
		// same orange as the name, full weight, not faint — one colour
		// says "Fable" twice
		money = orange
	}

	badgeSeg := claudeBadge
	moneySeg := ""
	if claudeBadge != "" {
		moneySeg = money + fmtMoney(fields.costCents) + "/" + fmtMoney(total) + reset
	} else if fields.costCents > 0 {
		moneySeg = money + fmtMoney(fields.costCents) + reset
	}

	styleSeg := ""
	if fields.styleName != "default" {
		styleSeg = gray + "⊙ " + fields.styleName + reset
	}

	// --- render ----------------------------------------------------------
	var out string
	switch {
	case cols < 60:
		computeLimits(g, now, false, false, fields, debugAll) // sample accumulation only
		left := add(modelSegSlim, ctxSeg)
		out = joinEdges(left, badgeSeg, cols, margin, g)
	case cols < 80:
		limits := computeLimits(g, now, false, false, fields, debugAll)
		left := add(modelSegSlim, ctxSeg)
		out = joinEdges(left, add(badgeSeg, limits), cols, margin, g)
	case cols < 100:
		limits := computeLimits(g, now, false, true, fields, debugAll)
		left := add(modelSegSlim, ctxSeg)
		right := add(badgeSeg, moneySeg)
		right = add(right, limits)
		out = joinEdges(left, right, cols, margin, g)
	default:
		limits := computeLimits(g, now, true, true, fields, debugAll)
		left := add(modelSeg, ctxSeg)
		if styleSeg != "" {
			left = add(left, styleSeg)
		}
		right := add(cacheSeg, badgeSeg)
		right = add(right, moneySeg)
		right = add(right, limits)
		out = joinEdges(left, right, cols, margin, g)
	}
	fmt.Print(out)
}

var fableRe = regexp.MustCompile(`[Ff]able`)
