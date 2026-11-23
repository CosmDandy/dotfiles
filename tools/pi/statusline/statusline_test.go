package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func renderStatus(t *testing.T, payload string, columns string) string {
	t.Helper()
	t.Setenv("TMPDIR", t.TempDir())
	t.Setenv("COLUMNS", columns)
	t.Setenv("CLAUDE_STATUSLINE_GLYPHS", "ascii")
	t.Setenv("CLAUDE_CLI_NOW", "1000000")
	input := filepath.Join(t.TempDir(), "input.json")
	if err := os.WriteFile(input, []byte(payload), 0600); err != nil {
		t.Fatal(err)
	}
	in, err := os.Open(input)
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	oldIn, oldOut := os.Stdin, os.Stdout
	os.Stdin, os.Stdout = in, w
	defer func() { os.Stdin, os.Stdout = oldIn, oldOut }()
	runStatusline(nil)
	w.Close()
	out, err := io.ReadAll(r)
	r.Close()
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}

func TestFooterPaletteIsMuted(t *testing.T) {
	for name, color := range map[string]string{
		"model": gray, "low": cyan, "medium": blue, "high": yellow,
		"xhigh": orange, "max/error": red, "context": green, "limits": dim,
	} {
		if !strings.HasPrefix(color, esc+"[2;") {
			t.Errorf("%s is not faint: %q", name, color)
		}
	}
	out := renderStatus(t, `{"model":{"display_name":"GPT"},"effort":{"level":"max"},"context_window":{"used_percentage":80}}`, "100")
	if !strings.Contains(out, gray+"GPT"+reset) || !strings.Contains(out, red+"max"+reset) || !strings.Contains(out, danger+"80%"+reset) {
		t.Fatalf("model and effort must stay muted next to urgent context: %q", out)
	}
}

func TestEffortIsColoredLowercaseWithoutIcons(t *testing.T) {
	for level, want := range map[string]struct{ label, color string }{
		"off": {"off", gray}, "minimal": {"minimal", gray},
		"low": {"low", cyan}, "medium": {"medium", blue},
		"high": {"high", yellow}, "xhigh": {"xhigh", orange}, "max": {"max", red},
		"MEDIUM": {"medium", gray},
	} {
		label, color := effortParts(level)
		if label != want.label || color != want.color {
			t.Errorf("%s: got (%q, %q)", level, label, color)
		}
	}
}

func TestRibbonLayout(t *testing.T) {
	out := renderStatus(t, `{"model":{"display_name":"GPT-6.1 SOL"},"effort":{"level":"medium"},"thinking":{"enabled":true},"context_window":{"used_percentage":24},"cost":{"total_cost_usd":12.34},"sessions":{"running":2,"waiting":3},"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1003600},"seven_day":{"used_percentage":20,"resets_at":1500000}}}`, "151")
	plain := ansiRe.ReplaceAllString(out, "")
	if !strings.HasPrefix(plain, "GPT-6.1 SOL · medium · 24%") || !strings.Contains(plain, "◉ 2 ○ 3 · 5h 42%") || !strings.Contains(plain, "7d 20%") {
		t.Fatal(plain)
	}
	for _, forbidden := range []string{"$", "you lose", "░", "█", "*", "\n", "identity"} {
		if strings.Contains(plain, forbidden) {
			t.Errorf("unexpected %q in %q", forbidden, plain)
		}
	}
	if visWidth(out, pickGlyphs()) != 151 {
		t.Fatalf("ribbon is not aligned: %q", plain)
	}
}

func TestContextColors(t *testing.T) {
	for pct, color := range map[int]string{0: green, 29: green, 30: warn, 44: warn, 45: danger, 99: danger} {
		data, _ := json.Marshal(map[string]any{"context_window": map[string]int{"used_percentage": pct}})
		out := renderStatus(t, string(data), "100")
		if !strings.Contains(out, color) {
			t.Errorf("%d: missing color %q in %q", pct, color, out)
		}
	}
}

func TestFiveHourContrastDoesNotReplaceForecastColor(t *testing.T) {
	for pct, color := range map[int]string{69: green, 70: warn, 89: warn, 90: danger} {
		out := renderStatus(t, fmt.Sprintf(`{"rate_limits":{"five_hour":{"used_percentage":%d,"resets_at":1003600}}}`, pct), "100")
		if !strings.Contains(out, fmt.Sprintf("%s5h %d%%%s", color, pct, reset)) ||
			!(strings.Contains(out, reset+dim+" (") || strings.Contains(out, reset+cyan+" (") ||
				strings.Contains(out, reset+green+" (") || strings.Contains(out, reset+red+" (")) {
			t.Errorf("%d: expected independent usage and forecast colors: %q", pct, out)
		}
	}
}

func TestWeeklyBudgetAndCountdown(t *testing.T) {
	const now = 1000000
	for _, tc := range []struct {
		name       string
		used       float64
		elapsed    int64
		color, end string
	}{
		{"under budget", 49, 84 * 3600, dim, ""},
		{"on schedule", 50, 84 * 3600, dim, ""},
		{"exactly 16h over", 50, 68 * 3600, warn, " -16ч00м"},
		{"fractional percent crosses threshold", 50.1, 68 * 3600, danger, " -16ч10м"},
		{"fractional overspend", 1.13, 6800, warn, " 0м"},
		{"forecast held back", 75, 101 * 3600, danger, " -25ч00м"},
		{"fractional second still before countdown", 70, 325662, danger, " -27ч08м"},
		{"first visible forecast", 75, 100*3600 + 48*60, danger, " -25ч12м -> 33ч"},
		{"imminent exhaustion", 99, 120 * 3600, danger, " -46ч19м -> 1ч"},
		{"less than an hour", 99.9, 120 * 3600, danger, " -47ч49м -> <1ч"},
		{"too early to forecast", 75, 3600, danger, " -125ч00м"},
		{"already exhausted", 100, 120 * 3600, danger, " -48ч00м"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := renderStatus(t, fmt.Sprintf(`{"rate_limits":{"seven_day":{"used_percentage":%.2f,"resets_at":%d}}}`, tc.used, now+weekSeconds-tc.elapsed), "100")
			want := fmt.Sprintf("%s7d %d%%%s%s", tc.color, int(tc.used), tc.end, reset)
			if !strings.Contains(out, want) {
				t.Fatalf("missing %q in %q", want, out)
			}
		})
	}
}

func TestExhaustedLimitUsesRefresh(t *testing.T) {
	payload := `{"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1003600}}}`
	out := renderStatus(t, payload, "100")
	plain := ansiRe.ReplaceAllString(out, "")
	if !strings.Contains(plain, "reset ") || strings.Contains(plain, "you lose") || strings.Contains(plain, "100%") {
		t.Fatal(plain)
	}
	t.Setenv("CLAUDE_STATUSLINE_GLYPHS", "nerd")
	g := pickGlyphs()
	if g.refresh != "\U000F0450" || visWidth(g.refresh, g) != 2 {
		t.Fatalf("wrong refresh glyph/width: %#v", g)
	}
}

func TestNarrowRibbonKeepsIdentityAndSessions(t *testing.T) {
	for _, width := range []string{"40", "60", "80", "100"} {
		out := renderStatus(t, `{"model":{"display_name":"GPT"},"effort":{"level":"high"},"context_window":{"used_percentage":24},"sessions":{"running":1}}`, width)
		plain := ansiRe.ReplaceAllString(out, "")
		if !strings.HasPrefix(plain, "GPT · high · 24%") || !strings.Contains(plain, "◉ 1") || strings.Contains(plain, "○ 0") {
			t.Fatal(width, plain)
		}
	}
}

func TestBothLimitsStayVisibleAtEveryWidth(t *testing.T) {
	for _, width := range []string{"1", "20", "40", "60", "80", "100", "151"} {
		out := renderStatus(t, `{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1003600},"seven_day":{"used_percentage":20,"resets_at":1500000}}}`, width)
		plain := ansiRe.ReplaceAllString(out, "")
		if !strings.Contains(plain, "5h 42%") || !strings.Contains(plain, "7d 20%") {
			t.Fatal(width, plain)
		}
		if width == "20" && !strings.Contains(plain, "\n") {
			t.Fatal("narrow ribbon must move limits to another line", plain)
		}
	}
}

func TestResetJitterDoesNotFreezeProviderPercentage(t *testing.T) {
	t.Setenv("TMPDIR", t.TempDir())
	const now int64 = 1000000
	dir := filepath.Join(os.Getenv("TMPDIR"), "claude-limit")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "five_hour")
	if err := os.WriteFile(path+".window", []byte(fmt.Sprintf("%d\n", now+3604)), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(fmt.Sprintf("%d 2200\n", now-300)), 0600); err != nil {
		t.Fatal(err)
	}
	resetAt := now + 3600
	result := fiveHourDev(3500, &resetAt, now)
	if result.pct100 != 3500 || result.reset == nil || *result.reset != resetAt {
		t.Fatalf("four-second reset jitter froze the percentage: %+v", result)
	}
	if samples := readSamples(path); len(samples) != 2 || samples[1].pct != 3500 {
		t.Fatalf("same-window history was not updated: %+v", samples)
	}
	resetAt += 10
	result = fiveHourDev(3600, &resetAt, now+60)
	if samples := readSamples(path); result.pct100 != 3600 || len(samples) != 3 {
		t.Fatalf("small forward jitter must not erase history: %+v %+v", result, samples)
	}
	result = fiveHourDev(3400, &resetAt, now+120)
	if result.pct100 != 3400 {
		t.Fatalf("history must not override a newer provider correction: %+v", result)
	}
}

func TestOnlyObservedLimitsAreShown(t *testing.T) {
	plain := ansiRe.ReplaceAllString(renderStatus(t, `{}`, "100"), "")
	if strings.Contains(plain, "5h") || strings.Contains(plain, "7d") {
		t.Fatal(plain)
	}
	plain = ansiRe.ReplaceAllString(renderStatus(t, `{"rate_limits":{"seven_day":{"used_percentage":0}}}`, "100"), "")
	if strings.Contains(plain, "5h") || !strings.Contains(plain, "7d 0%") {
		t.Fatal(plain)
	}
}
