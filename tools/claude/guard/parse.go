package main

import (
	"regexp"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// maxShellCDepth bounds recursion into nested `shell -c '...'` bodies so a
// pathological input (self-referential -c chains) cannot blow the stack.
const maxShellCDepth = 20

// ParseResult is the outcome of splitting a command into segments, mirroring
// the bash guard's segs(): one entry per simple command at command position
// (pipeline/;/&&/||/& members, subshells, $(...) and backtick bodies, and the
// recursively-parsed bodies of `shell -c '...'` invocations). Heredoc bodies
// are never turned into segments — they are data, not commands — even though
// the raw command text (used by has()) still contains them verbatim.
type ParseResult struct {
	Segments []string
	Fallback bool // true when mvdan/sh could not parse the command at all
}

var shellCNames = map[string]bool{
	"zsh": true, "bash": true, "sh": true, "dash": true, "ksh": true,
}

var (
	reLongFlag   = regexp.MustCompile(`^--[a-z][a-z-]*$`)
	reShortC     = regexp.MustCompile(`^-[a-zA-Z]*c$`)
	reShortFlags = regexp.MustCompile(`^-[a-zA-Z]+$`)
)

// parseCommand splits cmd into segments. On a parse failure it falls back to
// a quote-unaware split, per spec: never crash, never silently allow — has()
// rules still run against the raw text regardless of which path was taken.
func parseCommand(cmd string) ParseResult {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash), syntax.RecoverErrors(1000))
	f, err := parser.Parse(strings.NewReader(cmd), "")
	if err != nil || f == nil {
		return ParseResult{Segments: fallbackSplit(cmd), Fallback: true}
	}
	src := []byte(cmd)
	var out []string
	collectStmts(src, f.Stmts, &out, 0)
	return ParseResult{Segments: out}
}

// fallbackSplit is the dumb, quote-unaware split used only when the real
// parser rejects the command outright (unbalanced quotes, unclosed heredoc —
// inputs a model does sometimes produce). It mirrors the separator set the
// bash splitter uses at the character level: ; | & ( ) and backtick.
//
// It also splits on a bare newline. This is a deliberate deviation from a
// literal ; | & ( ) ` -only split: an unclosed heredoc (mvdan/sh cannot
// recover from one — there is no terminator to bound the body) is exactly
// the case the bash guard's own END-block re-walk exists for, so that a
// dangerous tail after the swallowed body is never silently allowed. Without
// splitting on newline here, that tail would stay glued to the opening line
// as one segment and every seg_head rule would miss it.
func fallbackSplit(cmd string) []string {
	var segs []string
	var cur strings.Builder
	flush := func() {
		if cur.Len() > 0 {
			segs = append(segs, cur.String())
			cur.Reset()
		}
	}
	for _, r := range cmd {
		switch r {
		case ';', '|', '&', '(', ')', '`', '\n':
			flush()
		default:
			cur.WriteRune(r)
		}
	}
	flush()
	return segs
}

func collectStmts(src []byte, stmts []*syntax.Stmt, out *[]string, depth int) {
	for _, st := range stmts {
		collectStmt(src, st, out, depth)
	}
}

// redirEnd is like (*syntax.Redirect).End(), except for a heredoc it stops
// right after the opening tag instead of extending through the body — the
// heredoc body is data, not part of any segment (see the package doc on
// Segments), even though the real Redirect.End() spans all the way to the
// terminator line to support round-tripping the source.
func redirEnd(r *syntax.Redirect) syntax.Pos {
	if r.Hdoc != nil {
		return r.Word.End()
	}
	return r.End()
}

func offsetSlice(src []byte, start, end syntax.Pos) string {
	so, eo := start.Offset(), end.Offset()
	if eo < so || eo > uint(len(src)) {
		return ""
	}
	return string(src[so:eo])
}

func collectStmt(src []byte, st *syntax.Stmt, out *[]string, depth int) {
	if st == nil {
		return
	}
	switch cmd := st.Cmd.(type) {
	case *syntax.CallExpr:
		end := cmd.End()
		for _, r := range st.Redirs {
			if re := redirEnd(r); re.Offset() > end.Offset() {
				end = re
			}
		}
		if text := offsetSlice(src, st.Pos(), end); text != "" {
			*out = append(*out, text)
		}
		for _, a := range cmd.Assigns {
			scanWord(src, a.Value, out, depth)
			if a.Array != nil {
				for _, el := range a.Array.Elems {
					scanWord(src, el.Value, out, depth)
				}
			}
		}
		for _, w := range cmd.Args {
			scanWord(src, w, out, depth)
		}
		expandShellC(src, cmd, out, depth)
	case *syntax.BinaryCmd:
		collectStmt(src, cmd.X, out, depth)
		collectStmt(src, cmd.Y, out, depth)
	case *syntax.Subshell:
		collectStmts(src, cmd.Stmts, out, depth)
	case *syntax.Block:
		collectStmts(src, cmd.Stmts, out, depth)
	case *syntax.IfClause:
		for ic := cmd; ic != nil; ic = ic.Else {
			collectStmts(src, ic.Cond, out, depth)
			collectStmts(src, ic.Then, out, depth)
		}
	case *syntax.WhileClause:
		collectStmts(src, cmd.Cond, out, depth)
		collectStmts(src, cmd.Do, out, depth)
	case *syntax.ForClause:
		if wi, ok := cmd.Loop.(*syntax.WordIter); ok {
			for _, w := range wi.Items {
				scanWord(src, w, out, depth)
			}
		}
		collectStmts(src, cmd.Do, out, depth)
	case *syntax.CaseClause:
		scanWord(src, cmd.Word, out, depth)
		for _, item := range cmd.Items {
			collectStmts(src, item.Stmts, out, depth)
		}
	case *syntax.FuncDecl:
		collectStmt(src, cmd.Body, out, depth)
	case *syntax.TimeClause:
		collectStmt(src, cmd.Stmt, out, depth)
	case *syntax.CoprocClause:
		collectStmt(src, cmd.Stmt, out, depth)
	}
	for _, r := range st.Redirs {
		// The heredoc TAG (r.Word) is scanned like any other word; the heredoc
		// BODY (r.Hdoc) is deliberately skipped — it is data for has(), never a
		// segment, matching the bash guard's split-vs-has asymmetry.
		scanWord(src, r.Word, out, depth)
	}
}

func scanWord(src []byte, w *syntax.Word, out *[]string, depth int) {
	if w == nil {
		return
	}
	for _, p := range w.Parts {
		scanWordPart(src, p, out, depth)
	}
}

func scanWordPart(src []byte, p syntax.WordPart, out *[]string, depth int) {
	switch x := p.(type) {
	case *syntax.CmdSubst:
		collectStmts(src, x.Stmts, out, depth)
	case *syntax.ProcSubst:
		collectStmts(src, x.Stmts, out, depth)
	case *syntax.DblQuoted:
		for _, pp := range x.Parts {
			scanWordPart(src, pp, out, depth)
		}
	case *syntax.ParamExp:
		if x.Repl != nil {
			scanWord(src, x.Repl.Orig, out, depth)
			scanWord(src, x.Repl.With, out, depth)
		}
		if x.Exp != nil {
			scanWord(src, x.Exp.Word, out, depth)
		}
	}
}

// expandShellC recognises `[/path/to/]shell [flags] -c BODY` (zsh, bash, sh,
// dash, ksh; flags bundled like -lc/-ec/-ic/-xc, or spelled out as --login,
// -o pipefail, etc. — the same shapes SHELLC_FLAGS in the bash guard allows)
// and recursively parses BODY as its own script, folding its segments into
// out. Unlike the bash guard, which extracts only one level via a single
// grep -Eo pass, this recurses fully: a nested `bash -c "zsh -c '...'"` is
// unwound all the way down (bounded by maxShellCDepth).
func expandShellC(src []byte, cmd *syntax.CallExpr, out *[]string, depth int) {
	if depth >= maxShellCDepth || len(cmd.Args) == 0 {
		return
	}
	name := wordLiteral(src, cmd.Args[0])
	if idx := strings.LastIndexByte(name, '/'); idx >= 0 {
		name = name[idx+1:]
	}
	if !shellCNames[name] {
		return
	}
	i := 1
	for i < len(cmd.Args) {
		lit := wordLiteral(src, cmd.Args[i])
		switch {
		case lit == "-o":
			i += 2 // "-o value"
		case reLongFlag.MatchString(lit):
			i++
		case reShortC.MatchString(lit):
			if i+1 >= len(cmd.Args) {
				return
			}
			body := rawWordText(src, cmd.Args[i+1])
			body = stripOuterQuotes(body)
			if body == "" {
				return
			}
			inner := parseCommand(body)
			collectFromSource(inner, out)
			if inner.Fallback {
				// Recursion into a fallback split cannot go deeper reliably;
				// stop here rather than mis-splitting further.
				return
			}
			return
		case reShortFlags.MatchString(lit):
			i++
		default:
			return
		}
	}
}

// collectFromSource merges a recursively-parsed sub-result's segments,
// re-running the shellc expansion for that nested body too (parseCommand
// already recursed into further nested -c bodies via expandShellC, since
// collectStmt calls it — this just appends what it produced).
func collectFromSource(r ParseResult, out *[]string) {
	*out = append(*out, r.Segments...)
}

// wordLiteral returns the literal value of a word when possible (via the
// AST), falling back to its raw source text. Used for flag/name matching
// where quoting is not expected in practice.
func wordLiteral(src []byte, w *syntax.Word) string {
	if lit := w.Lit(); lit != "" {
		return lit
	}
	return rawWordText(src, w)
}

func rawWordText(src []byte, w *syntax.Word) string {
	if w == nil {
		return ""
	}
	return offsetSlice(src, w.Pos(), w.End())
}

// stripOuterQuotes removes exactly one matching layer of surrounding quotes,
// the same way the bash guard's shellc_bodies does — a byte-level strip, not
// a real unescape, on purpose: the whole point is that the body TEXT (as
// written) is what gets re-parsed as a script.
func stripOuterQuotes(s string) string {
	if len(s) < 2 {
		return s
	}
	first, last := s[0], s[len(s)-1]
	if (first == '"' && last == '"') || (first == '\'' && last == '\'') {
		return s[1 : len(s)-1]
	}
	return s
}
