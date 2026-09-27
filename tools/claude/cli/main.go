// Command claude-cli bundles the hot-path Claude Code and tmux helpers that
// used to be separate shell/python scripts, each invoked on every keystroke,
// tool call or status tick. One process means one exec() and one runtime
// startup instead of five, which is most of what made the originals slow.
//
// Subcommands mirror the scripts they replace 1:1 in stdin/argv/env/file
// contract, so a caller can swap the command line without touching anything
// else:
//
//	statusline                 tools/claude/statusline.sh
//	sessions [full [sid]]      tools/claude/claude-sessions.py
//	pane-title <pid> <cmd> <s> tools/tmux/pane-title.sh
//	opsctx                     tools/claude/hooks/pretooluse-opsctx.sh
//	bashhint                   tools/claude/hooks/posttooluse-bashhint.sh
//
// Every subcommand must degrade the same way its script did: never crash,
// never hang, diagnostics to stderr only. See each file's own comments for
// the behaviour ported from the script of the same name.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "claude-cli: missing subcommand (statusline|sessions|pane-title|opsctx|bashhint)")
		os.Exit(2)
	}

	sub := os.Args[1]
	args := os.Args[2:]

	switch sub {
	case "statusline":
		runStatusline(args)
	case "sessions":
		runSessions(args)
	case "pane-title":
		runPaneTitle(args)
	case "opsctx":
		runOpsctx(args)
	case "bashhint":
		runBashhint(args)
	default:
		fmt.Fprintf(os.Stderr, "claude-cli: unknown subcommand %q\n", sub)
		os.Exit(2)
	}
}
