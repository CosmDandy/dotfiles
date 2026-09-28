package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"
)

// Each case runs the real subcommand: the test binary re-executes itself as
// claude-cli (see TestMain), so os.Exit, stdout and the environment behave
// exactly as they do under a hook. Expected outputs are the binary's own,
// pinned so a change to what a user sees has to be deliberate: on a mismatch
// the failure prints the new output as a Go literal to paste into the table.

// now pins the statusline clock through CLAUDE_CLI_NOW. The history fixtures
// sit exactly on the window and trend-lag boundaries, and the rendered reset
// clock changes width with the hour, so the run's own clock would move both.
const now = 1790553600 // 2026-09-28 00:00 UTC

func TestMain(m *testing.M) {
	if os.Getenv("CLAUDE_CLI_TEST_MAIN") == "1" {
		main()
		os.Exit(0)
	}
	os.Exit(m.Run())
}

type runOpts struct {
	home, tmp, stdin string
	env              []string
	combined         bool // stderr folded into the output, as tmux shows it
}

func run(t *testing.T, o runOpts, args ...string) string {
	t.Helper()
	cmd := exec.Command(os.Args[0], args...)
	cmd.Env = append([]string{
		"CLAUDE_CLI_TEST_MAIN=1",
		"PATH=" + os.Getenv("PATH"),
		"TZ=UTC",
		// a devcontainer, devpod or the Nix build sandbox would add pane-title's container marker
		"CLAUDE_CLI_IN_CONTAINER=0",
		"HOME=" + o.home,
		"TMPDIR=" + o.tmp,
		fmt.Sprintf("CLAUDE_CLI_NOW=%d", now),
	}, o.env...)
	cmd.Stdin = strings.NewReader(o.stdin)
	var out []byte
	var err error
	if o.combined {
		out, err = cmd.CombinedOutput()
	} else {
		out, err = cmd.Output()
	}
	if err != nil {
		t.Fatalf("claude-cli %v: %v\n%s", args, err, out)
	}
	return strings.TrimRight(string(out), "\n")
}

func writeFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()
	for name, body := range files {
		p := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func check(t *testing.T, what, got, want string) {
	t.Helper()
	if got != want {
		t.Errorf("%s differs\ngot:  %q\nwant: %q", what, got, want)
	}
}

type statuslineCase struct {
	name      string
	env       []string
	stdin     string
	state     map[string]string // files under TMPDIR before the run
	want      string
	wantState map[string]string // files under TMPDIR after the run
}

func TestStatusline(t *testing.T) {
	home := t.TempDir()
	writeFiles(t, filepath.Join(home, ".claude", "sessions"), sessionFixture)
	for _, c := range statuslineCases {
		t.Run(c.name, func(t *testing.T) {
			tmp := t.TempDir()
			writeFiles(t, tmp, c.state)
			got := run(t, runOpts{home: home, tmp: tmp, stdin: c.stdin, env: c.env}, "statusline")
			check(t, "output", got, c.want)
			for name, want := range c.wantState {
				b, _ := os.ReadFile(filepath.Join(tmp, name))
				check(t, name, string(b), want)
			}
		})
	}
}

type sessionsCase struct {
	name     string
	sessions map[string]string
	args     []string
	want     string
}

func TestSessions(t *testing.T) {
	for _, c := range sessionsCases {
		t.Run(c.name, func(t *testing.T) {
			home := t.TempDir()
			writeFiles(t, filepath.Join(home, ".claude", "sessions"), c.sessions)
			got := run(t, runOpts{home: home, tmp: t.TempDir()}, append([]string{"sessions"}, c.args...)...)
			check(t, "output", got, c.want)
		})
	}
}

type paneTitleCase struct {
	name, pid, cmd string
	sessions       map[string]string
	want           string
}

func TestPaneTitle(t *testing.T) {
	for _, c := range paneTitleCases {
		t.Run(c.name, func(t *testing.T) {
			home := t.TempDir()
			if err := os.MkdirAll(filepath.Join(home, ".claude", "sessions"), 0o755); err != nil {
				t.Fatal(err)
			}
			writeFiles(t, filepath.Join(home, ".claude", "sessions"), c.sessions)
			got := run(t, runOpts{home: home, tmp: t.TempDir(), combined: true}, "pane-title", c.pid, c.cmd, "mysession")
			check(t, "output", got, c.want)
		})
	}
}

// NOTE: shape only. What the tty lookup finds depends on everything else on
// that tty (Claude Code's own node process locally, nothing on a CI runner),
// so a live process only proves the path runs and returns a command name.
func TestPaneTitleLiveProcess(t *testing.T) {
	shape := regexp.MustCompile(`^mysession · \S+$`)
	for _, cmdName := range []string{"node", "999"} {
		t.Run(cmdName, func(t *testing.T) {
			p := exec.Command("sleep", "20")
			if err := p.Start(); err != nil {
				t.Fatal(err)
			}
			defer func() { _ = p.Process.Kill(); _ = p.Wait() }()
			got := run(t, runOpts{home: t.TempDir(), tmp: t.TempDir(), combined: true},
				"pane-title", fmt.Sprint(p.Process.Pid), cmdName, "mysession")
			if !shape.MatchString(got) {
				t.Errorf("got %q, want %s", got, shape)
			}
		})
	}
}

type opsctxCase struct {
	name, stdin, want string
}

func TestOpsctx(t *testing.T) {
	for _, c := range opsctxCases {
		t.Run(c.name, func(t *testing.T) {
			got := run(t, runOpts{home: t.TempDir(), tmp: t.TempDir(), stdin: c.stdin}, "opsctx")
			check(t, "output", got, c.want)
		})
	}
}

func TestOpsctxLatchFiresOnce(t *testing.T) {
	o := runOpts{home: t.TempDir(), tmp: t.TempDir(), stdin: latchProbe}
	if first := run(t, o, "opsctx"); first == "" {
		t.Fatal("first call in a session+domain is silent")
	}
	if second := run(t, o, "opsctx"); second != "" {
		t.Errorf("repeat call not silent: %q", second)
	}
}

func TestOpsctxStaleLatchCleanup(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".claude", ".state", "opsctx")
	writeFiles(t, dir, map[string]string{"stale.remote": ""})
	old := time.Now().Add(-10 * 24 * time.Hour)
	if err := os.Chtimes(filepath.Join(dir, "stale.remote"), old, old); err != nil {
		t.Fatal(err)
	}
	run(t, runOpts{home: home, tmp: t.TempDir(), stdin: latchProbe}, "opsctx")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	check(t, "latch dir", strings.Join(names, ","), staleCleanupLeft)
}

var sessionFixture = map[string]string{
	"18247.json": `{"pid":1,"sessionId":"9929c2da-cf7c-4fcf-9bf5-a46266200405","cwd":"/Users/cosmdandy/.dotfiles","startedAt":1790463559263,"procStart":"Sat Sep 26 22:17:51 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"bg","entrypoint":"cli","pidDomain":"darwin","messagingSocketPath":"/tmp/cc-socks/18247.sock","name":"performance audit bash-to-go","nameSince":1790466374828,"agent":"claude","jobId":"9929c2da","status":"idle","updatedAt":1790466829724,"statusUpdatedAt":1790466829724,"nameSource":"auto","formerNames":[{"name":"9929c2da","until":1790466374828,"sessionId":"9929c2da-cf7c-4fcf-9bf5-a46266200405"}]}`,
	"56777.json": `{"pid":1,"sessionId":"1f343825-2d93-4df8-90cb-5532809bbc4d","cwd":"/Users/cosmdandy/.dotfiles","startedAt":1790457490255,"procStart":"Sat Sep 26 21:18:04 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"interactive","entrypoint":"cli","pidDomain":"darwin","tmux":"dotfiles:@1.%1","messagingSocketPath":"/tmp/cc-socks/56777.sock","name":"dotfiles-c6","nameSource":"derived","nameSince":1790457490255,"status":"idle","updatedAt":1790457496013,"statusUpdatedAt":1790457490333,"parkedJobId":"141b98c4"}`,
	"57031.json": `{"pid":1,"sessionId":"4235eff6-bc74-4ff3-81fe-b81204aee27a","cwd":"/Users/cosmdandy/Projects/soniox-openai-shim","startedAt":1790457547295,"procStart":"Sat Sep 26 21:18:16 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"bg","entrypoint":"cli","pidDomain":"darwin","messagingSocketPath":"/tmp/cc-socks/57031.sock","name":"claude","nameSince":1790465842663,"agent":"claude","jobId":"4235eff6","nameSource":"peer","updatedAt":1790468502563,"status":"waiting","statusUpdatedAt":1790468502563,"formerNames":[{"name":"claude 1","until":1790465842663,"sessionId":"4235eff6-bc74-4ff3-81fe-b81204aee27a"}],"waitingFor":"permission prompt"}`,
	"57185.json": `{"pid":1,"sessionId":"f85fc845-f37e-4bd4-9d96-ff545b74833a","cwd":"/Users/cosmdandy/.dotfiles","startedAt":1790457501287,"procStart":"Sat Sep 26 21:18:20 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"bg","entrypoint":"cli","pidDomain":"darwin","messagingSocketPath":"/tmp/cc-socks/57185.sock","name":"claude agents","nameSince":1790461320768,"agent":"claude","jobId":"f85fc845","status":"idle","updatedAt":1790461320768,"statusUpdatedAt":1790461140747,"nameSource":"peer","formerNames":[{"name":"devcontainer klean setup","until":1790461320768,"sessionId":"f85fc845-f37e-4bd4-9d96-ff545b74833a"},{"name":"agent-system-research-klian","until":1790458707890,"sessionId":"f85fc845-f37e-4bd4-9d96-ff545b74833a"},{"name":"f85fc845","until":1790458244006,"sessionId":"f85fc845-f37e-4bd4-9d96-ff545b74833a"}]}`,
	"76518.json": `{"pid":1,"sessionId":"c2c696ae-53f1-40bc-ad08-ee537c2f314f","cwd":"/Users/cosmdandy","startedAt":1790461974142,"procStart":"Sat Sep 26 22:32:52 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"interactive","entrypoint":"cli","pidDomain":"darwin","tmux":"dotfiles:@5.%5","messagingSocketPath":"/tmp/cc-socks/76518.sock","name":"bitwarden secrets sync devpod","nameSource":"auto","nameSince":1790461974200,"updatedAt":1790467074397,"status":"waiting","statusUpdatedAt":1790467074397,"waitingFor":"dialog open"}`,
	"99358.json": `{"pid":1,"sessionId":"413069a1-4a04-442d-810d-9cc0bce44b7c","cwd":"/Users/cosmdandy/.dotfiles","startedAt":1790466370095,"procStart":"Sat Sep 26 23:00:36 2026","version":"2.1.283","peerProtocol":1,"peerFeatures":["notify_idle","reply_across_default_dirs","artifact_yield"],"kind":"bg","entrypoint":"cli","pidDomain":"darwin","messagingSocketPath":"/tmp/cc-socks/99358.sock","name":"413069a1","nameSince":1790466370095,"agent":"claude","jobId":"413069a1","spare":true,"status":"idle","updatedAt":1790466369935,"statusUpdatedAt":1790466369935}`,
}

var statuslineCases = []statuslineCase{
	{
		name: "wide 120, full segments",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case01-basic"}
`,
		want: "\x1b[34m󰧑 Opus 5\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[38;5;11m● High\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                                           \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰦖 0% (0:00)\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰨳 10%\x1b[0m",
	},
	{
		name: "narrow <60",
		env:  []string{"COLUMNS=50"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case02-narrow50"}
`,
		want: "\x1b[34m󰧑 Opus 5\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m              \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m",
	},
	{
		name: "narrow <80",
		env:  []string{"COLUMNS=70"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case03-narrow70"}
`,
		want: "\x1b[34m󰧑 Opus 5\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                   \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰦖 0% (0:00)\x1b[0m",
	},
	{
		name: "narrow <100",
		env:  []string{"COLUMNS=90"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case04-narrow90"}
`,
		want: "\x1b[34m󰧑 Opus 5\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                      \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰦖 0% (0:00)\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰨳 10%\x1b[0m",
	},
	{
		name: "ascii glyphs",
		env:  []string{"COLUMNS=120", "CLAUDE_STATUSLINE_GLYPHS=ascii"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case05-ascii"}
`,
		want: "\x1b[34m* Opus 5\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[38;5;11m● High\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                                             \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m5h 0% (0:00)\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m7d 10%\x1b[0m",
	},
	{
		name: "debug shows every segment",
		env:  []string{"COLUMNS=120", "CLAUDE_STATUSLINE_DEBUG=1"},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":180000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.0,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case06-debug"}
`,
		want: "\x1b[34m󰧑 Opus 5\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[38;5;11m● High\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                                   \x1b[32m◎ 99%\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰦖 0% (0:00)\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰨳 10%\x1b[0m",
	},
	{
		name: "no session_id",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0}}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                               \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "fable model - orange",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Fable","id":"fable-1"},"cost":{"total_cost_usd":2.5},"session_id":"case08-fable"}
`,
		want: "\x1b[38;5;9mFable\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                                \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;9m$3/$3\x1b[0m",
	},
	{
		name: "context bar red threshold",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":90},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"session_id":"case09-red"}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m█\x1b[31m█\x1b[31m█\x1b[31m█\x1b[31m█\x1b[31m░\x1b[0m \x1b[31m90%\x1b[0m                                                                               \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "1M context window marker",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10,"context_window_size":1000000},"model":{"display_name":"Opus (1M context)"},"cost":{"total_cost_usd":0},"session_id":"case10-1m"}
`,
		want: "\x1b[34mOpus\x1b[0m\x1b[2;38;5;11m 1M\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                              \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "five-hour window fully spent",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":1.0,"resets_at":1893456000}},"session_id":"case11-over100"}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰦖 1% (0:00)\x1b[0m",
	},
	{
		name: "no rate_limits object at all",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"session_id":"case12-nolimits"}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                               \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "TERM=dumb falls back to ascii",
		env:  []string{"COLUMNS=120", "TERM=dumb", "CLAUDE_STATUSLINE_GLYPHS="},
		stdin: `{"context_window":{"used_percentage":42.7,"context_window_size":200000,"current_usage":{"cache_read_input_tokens":8000,"input_tokens":500,"cache_creation_input_tokens":200}},"model":{"display_name":"Opus 5","id":"opus-5"},"output_style":{"name":"default"},"effort":{"level":"high"},"thinking":{"enabled":true},"agent":{"name":"claude"},"cost":{"total_cost_usd":1.234},"rate_limits":{"five_hour":{"used_percentage":0.42,"resets_at":1893456000},"seven_day":{"used_percentage":10,"resets_at":1893456000}},"session_id":"case13-termdumb"}
`,
		want: "\x1b[34m* Opus 5\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[38;5;11m● High\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m█\x1b[32m█\x1b[33m█\x1b[31m▏\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[33m42%\x1b[0m                                             \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m5h 0% (0:00)\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m7d 10%\x1b[0m",
	},
	{
		name: "non-default output style",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":5},"model":{"display_name":"Sonnet"},"output_style":{"name":"explanatory"},"cost":{"total_cost_usd":0},"session_id":"case14-style"}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m▌\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m5%\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m⊙ explanatory\x1b[0m                                                                \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "xhigh effort",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":5},"model":{"display_name":"Sonnet"},"effort":{"level":"xhigh"},"cost":{"total_cost_usd":0},"session_id":"case15-xhigh"}
`,
		want: "\x1b[34mSonnet\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[33m◉ xHigh\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m▌\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m5%\x1b[0m                                                                      \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "max effort",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":5},"model":{"display_name":"Sonnet"},"effort":{"level":"max"},"cost":{"total_cost_usd":0},"session_id":"case16-max"}
`,
		want: "\x1b[34mSonnet\x1b[0m\x1b[2;38;5;11m · \x1b[0m\x1b[31m◈ Max\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m▌\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m5%\x1b[0m                                                                        \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "unknown effort label falls back",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":5},"model":{"display_name":"Sonnet"},"effort":{"level":"weird"},"cost":{"total_cost_usd":0},"session_id":"case17-unknown"}
`,
		want: "\x1b[34mSonnet\x1b[0m\x1b[2;38;5;11m · \x1b[0mweird\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m▌\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m5%\x1b[0m                                                                        \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "custom agent suffix",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":5},"model":{"display_name":"Sonnet"},"agent":{"name":"reviewer"},"cost":{"total_cost_usd":0},"session_id":"case18-agent"}
`,
		want: "\x1b[34mSonnet\x1b[0m\x1b[38;5;11m ▸ reviewer\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m▌\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m5%\x1b[0m                                                                     \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name:  "empty payload {}",
		env:   []string{"COLUMNS=120"},
		stdin: `{}`,
		want:  "\x1b[34mClaude\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m░\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m0%\x1b[0m                                                                                \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m",
	},
	{
		name: "accelerating 5h burn -> negative dev, trend down",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":0.45,"resets_at":1790556600}},"session_id":"case19-accel"}
`,
		state: map[string]string{
			"claude-limit/five_hour": `1790552400 1000
1790552700 1500
1790553000 2500
1790553300 4000
`,
			"claude-limit/five_hour.window": `1790556600
`,
		},
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                   \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[31m󰦖 40% -20м (0:50 ⟶ 0:30)\x1b[0m",
		wantState: map[string]string{
			"claude-limit/five_hour": `1790552400 1000
1790552700 1500
1790553000 2500
1790553300 4000
`,
			"claude-limit/five_hour.window": `1790556600
`,
		},
	},
	{
		name: "decelerating 5h burn -> trend up",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"rate_limits":{"five_hour":{"used_percentage":0.28,"resets_at":1790556600}},"session_id":"case20-decel"}
`,
		state: map[string]string{
			"claude-limit/five_hour": `1790551800 500
1790552100 1200
1790552400 1800
1790552700 2200
1790553000 2500
1790553300 2700
`,
			"claude-limit/five_hour.window": `1790556600
`,
		},
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                               \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m󰦖 27% (0:50)\x1b[0m",
		wantState: map[string]string{
			"claude-limit/five_hour": `1790551800 500
1790552100 1200
1790552400 1800
1790552700 2200
1790553000 2500
1790553300 2700
`,
			"claude-limit/five_hour.window": `1790556600
`,
		},
	},
	{
		name: "week deviation, no five-hour history",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0},"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1790556600}},"session_id":"case21-weekdev"}
`,
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                       \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$0/$0\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[38;5;11m󰨳 5%\x1b[0m",
		wantState: map[string]string{
			"claude-limit/five_hour":        ``,
			"claude-limit/five_hour.window": ``,
		},
	},
	{
		name: "own share / everyone's total, several session files",
		env:  []string{"COLUMNS=120"},
		stdin: `{"context_window":{"used_percentage":10},"model":{"display_name":"Sonnet"},"cost":{"total_cost_usd":0.75},"session_id":"case22-multisession"}
`,
		state: map[string]string{
			"claude-sessions/9929c2da-cf7c-4fcf-9bf5-a46266200405": `144
`,
			"claude-sessions/f85fc845-f37e-4bd4-9d96-ff545b74833a": `2070
`,
		},
		want: "\x1b[34mSonnet\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[32m█\x1b[32m░\x1b[32m░\x1b[33m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[31m░\x1b[0m \x1b[32m10%\x1b[0m                                                                              \x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m \x1b[2;38;5;11m·\x1b[0m \x1b[2;38;5;11m$1/$23\x1b[0m",
	},
}

var sessionsCases = []sessionsCase{
	{
		name:     "bare mode on recorded snapshot",
		sessions: sessionFixture,
		args:     []string{},
		want:     "○ 3 󰌾 1",
	},
	{
		name:     "full mode on recorded snapshot",
		sessions: sessionFixture,
		args:     []string{"full"},
		want:     "\x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m",
	},
	{
		name:     "full mode, self_id excludes a recorded session",
		sessions: sessionFixture,
		args:     []string{"full", "413069a1-4a04-442d-810d-9cc0bce44b7c"},
		want:     "\x1b[38;5;3m○ 3\x1b[0m \x1b[38;5;1m󰌾 1\x1b[0m",
	},
	{
		name: "running+waiting+approval all present (full)",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy"}`,
			"2.json": `{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}`,
			"3.json": `{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"permission prompt"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "bare mode omits running",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy"}`,
			"2.json": `{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}`,
			"3.json": `{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"permission prompt"}`,
		},
		args: []string{},
		want: "",
	},
	{
		name: "bg idle counts as waiting",
		sessions: map[string]string{
			"1.json": `{"kind":"bg","pid":1,"status":"idle"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "spare session excluded",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy","spare":true}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "parked session excluded",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy","parkedJobId":"x"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "unknown kind excluded",
		sessions: map[string]string{
			"1.json": `{"kind":"other","pid":1,"status":"busy"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "implausible pid treated consistently",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":999999997,"status":"busy"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "non-integer pid excluded",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":"not-an-int","status":"busy"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "float-typed pid excluded",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":123.0,"status":"busy"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "no self_id arg and no sessionId field",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy"}`,
		},
		args: []string{"full"},
		want: "",
	},
	{
		name: "explicit empty self_id matches empty sessionId",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"busy","sessionId":""}`,
		},
		args: []string{"full", ""},
		want: "",
	},
}

var paneTitleCases = []paneTitleCase{
	{
		name:     "zsh shortcut, no badge",
		pid:      "12345",
		cmd:      "zsh",
		sessions: nil,
		want:     "mysession",
	},
	{
		name:     "bash shortcut, no badge",
		pid:      "12345",
		cmd:      "bash",
		sessions: nil,
		want:     "mysession",
	},
	{
		name:     "fish shortcut, no badge",
		pid:      "12345",
		cmd:      "fish",
		sessions: nil,
		want:     "mysession",
	},
	{
		name:     "other command, no badge",
		pid:      "12345",
		cmd:      "nvim",
		sessions: nil,
		want:     "mysession · nvim",
	},
	{
		name: "other command, with badge",
		pid:  "12345",
		cmd:  "nvim",
		sessions: map[string]string{
			"1.json": `{"kind":"interactive","pid":1,"status":"waiting","waitingFor":"input needed"}`,
		},
		want: "mysession · nvim",
	},
	{
		name:     "node cmd, nonexistent pid",
		pid:      "99999999",
		cmd:      "node",
		sessions: nil,
		want:     "mysession · node",
	},
}

const latchProbe = `{"tool_input":{"command":"ssh host"},"session_id":"opsctx-latch"}
`

var opsctxCases = []opsctxCase{
	{
		name: "command_position_and",
		stdin: `{"tool_input":{"command":"echo hi && ssh host"},"session_id":"opsctx-x4"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "command_position_semicolon",
		stdin: `{"tool_input":{"command":"echo hi; ssh host"},"session_id":"opsctx-x3"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name:  "latch_probe",
		stdin: latchProbe,
		want:  "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "metal_ipmitool",
		stdin: `{"tool_input":{"command":"ipmitool power status"},"session_id":"opsctx-m1"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: BARE-METAL / BMC. Load the ops-metal skill now. Non-negotiable: prove a live console (sol info AND actual output) BEFORE any power, boot-order or BIOS change; power soft before reset/off; bootdev is one-shot unless options=persistent; never mc reset cold while the BMC is your only path in; never flash firmware over that only path; pass credentials via -E or -f, never -P.\"}}",
	},
	{
		name: "metal_racadm",
		stdin: `{"tool_input":{"command":"racadm serveraction powerstatus"},"session_id":"opsctx-m2"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: BARE-METAL / BMC. Load the ops-metal skill now. Non-negotiable: prove a live console (sol info AND actual output) BEFORE any power, boot-order or BIOS change; power soft before reset/off; bootdev is one-shot unless options=persistent; never mc reset cold while the BMC is your only path in; never flash firmware over that only path; pass credentials via -E or -f, never -P.\"}}",
	},
	{
		name: "metal_redfishtool",
		stdin: `{"tool_input":{"command":"redfishtool -r bmc raw GET /redfish/v1"},"session_id":"opsctx-m3"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: BARE-METAL / BMC. Load the ops-metal skill now. Non-negotiable: prove a live console (sol info AND actual output) BEFORE any power, boot-order or BIOS change; power soft before reset/off; bootdev is one-shot unless options=persistent; never mc reset cold while the BMC is your only path in; never flash firmware over that only path; pass credentials via -E or -f, never -P.\"}}",
	},
	{
		name: "missing_session_id",
		stdin: `{"tool_input":{"command":"ssh host"}}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "multiline_domain_second_line",
		stdin: `{"tool_input":{"command":"echo hi\nssh host uptime"},"session_id":"opsctx-ml1"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "multiple_domains_last_wins",
		stdin: `{"tool_input":{"command":"ssh host; ip a"},"session_id":"opsctx-x5"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).\"}}",
	},
	{
		name: "net_dig",
		stdin: `{"tool_input":{"command":"dig example.com"},"session_id":"opsctx-n4"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).\"}}",
	},
	{
		name: "net_ip",
		stdin: `{"tool_input":{"command":"ip a"},"session_id":"opsctx-n1"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).\"}}",
	},
	{
		name: "net_nft",
		stdin: `{"tool_input":{"command":"nft list ruleset"},"session_id":"opsctx-n3"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).\"}}",
	},
	{
		name: "net_tcpdump",
		stdin: `{"tool_input":{"command":"tcpdump -i eth0 -c 5"},"session_id":"opsctx-n2"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).\"}}",
	},
	{
		name: "no_domain_plain",
		stdin: `{"tool_input":{"command":"ls -la"},"session_id":"opsctx-x1"}
`,
		want: "",
	},
	{
		name: "quoted_mention",
		stdin: `{"tool_input":{"command":"git commit -m \"run ssh later\""},"session_id":"opsctx-x2"}
`,
		want: "",
	},
	{
		name: "remote_ansible",
		stdin: `{"tool_input":{"command":"ansible-playbook site.yml"},"session_id":"opsctx-r4"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "remote_rsync",
		stdin: `{"tool_input":{"command":"rsync -av a b"},"session_id":"opsctx-r3"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "remote_scp",
		stdin: `{"tool_input":{"command":"scp -r a b"},"session_id":"opsctx-r2"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "remote_ssh",
		stdin: `{"tool_input":{"command":"ssh host.example.com"},"session_id":"opsctx-r1"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.\"}}",
	},
	{
		name: "vm_limactl",
		stdin: `{"tool_input":{"command":"limactl start default"},"session_id":"opsctx-v2"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.\"}}",
	},
	{
		name: "vm_utmctl",
		stdin: `{"tool_input":{"command":"utmctl start myvm"},"session_id":"opsctx-v1"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.\"}}",
	},
	{
		name: "vm_virsh",
		stdin: `{"tool_input":{"command":"virsh list"},"session_id":"opsctx-v3"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.\"}}",
	},
	{
		name: "vm_virt_sysprep",
		stdin: `{"tool_input":{"command":"virt-sysprep -d vm1"},"session_id":"opsctx-v4"}
`,
		want: "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.\"}}",
	},
}

const staleCleanupLeft = "opsctx-latch.remote"
