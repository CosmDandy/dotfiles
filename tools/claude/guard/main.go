// Command guard is the Go port of tools/claude/hooks/pretooluse-guard.sh: a
// PreToolUse hook for Claude Code's Bash tool. It reads the hook's JSON on
// stdin and prints a permission decision (deny/ask) on stdout, or nothing at
// all to allow silently. It runs on every Bash call in every permission
// mode, including --dangerously-skip-permissions, so it must never crash and
// never hang — diagnostics go to stderr only, never stdout.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
)

type hookInput struct {
	Cwd       string `json:"cwd"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

func main() {
	raw, err := io.ReadAll(bufio.NewReader(os.Stdin))
	if err != nil {
		fmt.Fprintln(os.Stderr, "guard: reading stdin:", err)
		os.Exit(0)
	}

	var in hookInput
	if err := json.Unmarshal(raw, &in); err != nil {
		fmt.Fprintln(os.Stderr, "guard: parsing input JSON:", err)
		os.Exit(0)
	}

	cmd := in.ToolInput.Command
	if cmd == "" {
		return
	}

	// Cheap prefilter: skip parsing entirely when the command cannot possibly
	// match any rule below. Must stay a strict superset of every rule's
	// trigger words.
	if !reGated.MatchString(cmd) {
		return
	}

	cwd := in.Cwd
	if cwd == "" {
		cwd, err = os.Getwd()
		if err != nil {
			cwd = "."
		}
	}

	result := parseCommand(cmd)
	ctx := &Ctx{cmd: cmd, cwd: cwd, segs: result.Segments}
	decision := evaluate(ctx)
	if decision == noDecision {
		return
	}
	emit(decision)
}

func emit(d Decision) {
	out := map[string]any{
		"hookSpecificOutput": map[string]any{
			"hookEventName":            "PreToolUse",
			"permissionDecision":       d.Verdict,
			"permissionDecisionReason": d.Reason,
		},
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(out); err != nil {
		fmt.Fprintln(os.Stderr, "guard: encoding output:", err)
	}
}
