package main

// Port of tools/claude/claude-sessions.py: Claude session counters for the
// window title and for the statusline.
//
// A session that stops to ask goes silent: hooks run without a controlling
// terminal, so nothing rings, and noticing it means looking at every window
// in turn.
//
// The source is ~/.claude/sessions/<pid>.json — one file per live session,
// written by Claude Code itself and covering interactive windows as well as
// background jobs. ~/.claude/jobs/ was the obvious candidate and is the wrong
// one: only background tasks ever get a directory there, so every
// interactive window — the ones actually worth pointing at — was invisible.
//
// The two fields that matter are `status` and `waitingFor`, set together:
//
//	if (waitingFor !== undefined) return {status:"waiting", waitingFor, ...}
//	return {status: isLoading||delegatedActive ? "busy" : "idle", ...}
//
// `waitingFor` names the kind of wait — "dialog open", "input needed", "goal
// proposal", "sandbox request" — and falls back to "permission prompt", which
// is what makes a permission request tellable from an ordinary question.
// Hence three states:
//
//	running   status == busy
//	waiting   status == waiting, or a background job gone idle (it finished
//	          and wants an answer; an idle interactive window is just a window)
//	approval  waitingFor == "permission prompt"
//
// Two outputs, because the two places answer different questions. The window
// title asks "am I needed?" — waiting and approval only, no colour, since the
// system font draws it. The statusline asks "what is going on?" — all three,
// coloured.
//
// Scope is the machine it runs on: the Mac counts local sessions, a
// devcontainer the ones inside it, an ssh host the ones there.

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

const permissionWait = "permission prompt"

// Solarized: cyan for work in progress, yellow for "your turn", red for
// "cannot go on without you". All three hold on both the light and the dark
// variant.
const (
	runColour     = 37
	waitColour    = 136
	approveColour = 160
)

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return fallback
}

func runIcon() string     { return envOr("CLAUDE_RUN_ICON", "◉") }
func waitIcon() string    { return envOr("CLAUDE_WAIT_ICON", "○") }
func approveIcon() string { return envOr("CLAUDE_APPROVE_ICON", "\U000F033E") }

// sessionsDir returns ~/.claude/sessions, same as the python script's
// os.path.expanduser("~") — both read $HOME, so parity tests point it at
// recorded fixtures by setting HOME, with no extra knob needed.
func sessionsDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".claude", "sessions")
}

// alive mirrors the python: os.kill(pid, 0) raising ProcessLookupError means
// gone; PermissionError (someone else's process) still means "running".
func alive(pid int) bool {
	err := syscall.Kill(pid, 0)
	if err == nil {
		return true
	}
	if err == syscall.ESRCH {
		return false
	}
	return true // EPERM or anything else: something is running under that pid
}

// sessionCounts scans sessionsDir() for interactive/bg session files and
// tallies running/waiting/approval, excluding selfID (the session drawing
// its own statusline is busy by definition and would otherwise always show
// a permanent "1" for itself).
//
// selfID mirrors python's `self_id = sys.argv[2] if len(sys.argv) > 2 else
// None`, then `data.get("sessionId") == self_id`: nil is "no argument given"
// and matches only a session file whose sessionId is itself absent or null
// (an edge case, but the comparison must be exact for byte-identical
// output) — a non-nil, possibly-empty string only matches an equal string
// value.
func sessionCounts(selfID *string) (running, waiting, approval int) {
	dir := sessionsDir()
	entries, err := os.ReadDir(dir) // ReadDir already sorts by name, like sorted(scandir(), key=name)
	if err != nil {
		return 0, 0, 0
	}

	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".json") {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}

		dec := json.NewDecoder(strings.NewReader(string(raw)))
		dec.UseNumber()
		var data map[string]any
		if err := dec.Decode(&data); err != nil {
			continue
		}

		// spare is a pre-warmed process waiting to be adopted, parked is a job
		// put aside — neither is a session anyone is waiting on. Stale files
		// are rare (Claude Code prunes its own) but a crash leaves one behind.
		kind, _ := data["kind"].(string)
		if kind != "interactive" && kind != "bg" {
			continue
		}
		if spare, ok := data["spare"].(bool); ok && spare {
			continue
		}
		if pj, ok := data["parkedJobId"]; ok && pj != nil {
			continue
		}
		sessionIDVal, hasSessionID := data["sessionId"]
		if selfID == nil {
			if !hasSessionID || sessionIDVal == nil {
				continue
			}
		} else if hasSessionID {
			if sid, ok := sessionIDVal.(string); ok && sid == *selfID {
				continue
			}
		}

		pidNum, ok := data["pid"].(json.Number)
		if !ok {
			continue
		}
		// isinstance(pid, int) in python: a JSON number written with a
		// fraction or exponent decodes as float there and fails the check.
		if strings.ContainsAny(pidNum.String(), ".eE") {
			continue
		}
		pid64, err := strconv.ParseInt(pidNum.String(), 10, 64)
		if err != nil || !alive(int(pid64)) {
			continue
		}

		status, _ := data["status"].(string)
		waitingFor, _ := data["waitingFor"].(string)
		switch {
		case waitingFor == permissionWait:
			approval++
		case status == "waiting":
			waiting++
		case status == "busy":
			running++
		case status == "idle" && kind == "bg":
			waiting++
		}
	}

	return running, waiting, approval
}

// sessionBadge renders the counters exactly as claude-sessions.py's main()
// does: bare mode is waiting+approval only, uncoloured (drawn by the system
// font in the window title); full mode adds running, coloured (the
// statusline, which draws its own colours already).
func sessionBadge(full bool, selfID *string) string {
	running, waiting, approval := sessionCounts(selfID)

	type part struct {
		icon   string
		number int
		colour int
	}
	parts := []part{
		{waitIcon(), waiting, waitColour},
		{approveIcon(), approval, approveColour},
	}
	if full {
		parts = append([]part{{runIcon(), running, runColour}}, parts...)
	}

	var out []string
	for _, p := range parts {
		if p.number <= 0 {
			continue
		}
		piece := fmt.Sprintf("%s %d", p.icon, p.number)
		if full {
			piece = fmt.Sprintf("\x1b[38;5;%dm%s\x1b[0m", p.colour, piece)
		}
		out = append(out, piece)
	}

	return strings.Join(out, " ")
}

// runSessions implements the `sessions [full [session_id]]` subcommand,
// argv-compatible with claude-sessions.py.
func runSessions(args []string) {
	full := len(args) > 0 && args[0] == "full"
	var selfID *string
	if len(args) > 1 {
		selfID = &args[1]
	}
	badge := sessionBadge(full, selfID)
	if badge != "" {
		fmt.Print(badge)
	}
}
