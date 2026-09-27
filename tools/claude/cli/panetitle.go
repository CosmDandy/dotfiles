package main

// Port of tools/tmux/pane-title.sh: builds the tmux window title from the
// pane's pid, its current foreground command and the tmux session name.
// Invoked by tmux itself on every status-interval tick per client
// (`set-titles-string #(...)`), so it must stay a fast, no-argument-flags
// drop-in: pane-title <pane_pid> <pane_current_command> <session>.

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// containerGlyph is U+F01A7 (md-application-brackets-outline in some nerd
// font sets) — the window title is drawn by the system font, not the
// terminal font, so it needs its own glyph rather than reusing the dotted
// circle used elsewhere (a speck in SF Pro).
const containerGlyph = "\U000F01A7"

// inContainer mirrors pane-title.sh's in_container(): true only on Linux,
// and only inside one of the container/VZ/WSL markers it checks. CLAUDE_CLI_
// IN_CONTAINER overrides it for tests ("1"/"0"), bypassing the filesystem —
// unset behaviour is unchanged.
func inContainer() bool {
	if v, ok := os.LookupEnv("CLAUDE_CLI_IN_CONTAINER"); ok {
		return v == "1"
	}
	if runtime.GOOS != "linux" {
		return false
	}
	exists := func(path string) bool {
		_, err := os.Lstat(path)
		return err == nil
	}
	if exists("/proc/vz") && !exists("/proc/bc") {
		return true
	}
	if exists("/run/host/container-manager") {
		return true
	}
	if exists("/dev/incus/sock") {
		return true
	}
	if exists("/run/.containerenv") {
		return true
	}
	if exists("/.dockerenv") {
		return true
	}
	if raw, err := os.ReadFile("/run/systemd/container"); err == nil {
		line := strings.SplitN(string(raw), "\n", 2)[0]
		if line != "wsl" {
			return true
		}
	}
	return false
}

// paneTTY is `ps -o tty= -p pid`, trimmed. CLAUDE_CLI_PANE_TITLE_TTY
// overrides it for tests.
func paneTTY(pid string) string {
	if v, ok := os.LookupEnv("CLAUDE_CLI_PANE_TITLE_TTY"); ok {
		return v
	}
	out, err := exec.Command("ps", "-o", "tty=", "-p", pid).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// ttyHasClaude is `ps -t tty -o args=` searched for "claude".
// CLAUDE_CLI_PANE_TITLE_ARGS overrides the ps output for tests.
func ttyHasClaude(tty string) bool {
	var out string
	if v, ok := os.LookupEnv("CLAUDE_CLI_PANE_TITLE_ARGS"); ok {
		out = v
	} else {
		raw, err := exec.Command("ps", "-t", tty, "-o", "args=").Output()
		if err != nil {
			return false
		}
		out = string(raw)
	}
	return strings.Contains(out, "claude")
}

func runPaneTitle(args []string) {
	var panePID, cmd, session string
	if len(args) > 0 {
		panePID = args[0]
	}
	if len(args) > 1 {
		cmd = args[1]
	}
	if len(args) > 2 {
		session = args[2]
	}

	prefix := session
	if inContainer() {
		prefix = containerGlyph + "  " + session
	}

	// Same glyphs as everywhere else via sessionBadge's own env overrides.
	badge := sessionBadge(false, nil)

	switch cmd {
	case "zsh", "bash", "fish":
		if badge != "" {
			fmt.Printf("%s · %s\n", prefix, badge)
		} else {
			fmt.Println(prefix)
		}
		return
	}

	label := cmd

	// NOTE: Claude Code is either a node wrapper (devcontainers) or the
	// native binary, whose comm is its version number — so "claude" is
	// looked for in the args of any process on the pane's tty, which does
	// not depend on the depth of the process tree.
	if cmd == "node" || (len(cmd) > 0 && cmd[0] >= '0' && cmd[0] <= '9') {
		if tty := paneTTY(panePID); tty != "" && ttyHasClaude(tty) {
			label = "claude"
		}
	}

	if badge != "" {
		fmt.Printf("%s · %s · %s\n", prefix, label, badge)
	} else {
		fmt.Printf("%s · %s\n", prefix, label)
	}
}
