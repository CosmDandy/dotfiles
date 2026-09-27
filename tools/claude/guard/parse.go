package main

import (
	"regexp"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// maxShellCDepth bounds recursion into nested `shell -c '...'` bodies so a
// pathological input (self-referential -c chains) cannot blow the stack.
const maxShellCDepth = 20

// maxSubstNesting is a cheap pre-parse guard against pathological
// $(...)-in-$(...) nesting (e.g. `echo $($($(...)))` thousands deep), which
// makes both mvdan/sh's parser and our own AST walk slow and memory-hungry.
// It is a rough, quote-unaware scan on purpose — a safety valve, not a
// correctness check — so a false trip just means an extra fallback split,
// never a crash or a silent allow.
const maxSubstNesting = 256

// Segment is one simple command at command position — see ParseResult.
// GitCDir/HasGitCDir hold the -C directory of a `git`-headed segment,
// resolved structurally from its argument words (see gitDashCFlag) rather
// than by regex over Text: Text may itself contain an embedded "-C" that
// belongs to a heredoc body nested inside an argument (e.g. a commit
// message built from `$(cat <<'EOF' ... EOF)`), and a text search cannot
// tell that occurrence from a real global flag.
type Segment struct {
	Text       string
	GitCDir    string
	HasGitCDir bool
	// GitDirAmbiguous is true for a git-headed segment carrying a
	// --git-dir/--work-tree flag or a GIT_DIR=/GIT_WORK_TREE= env-var
	// assignment — either relocates the repo a push targets in a way
	// pushNeedsConfirm cannot resolve structurally (unlike -C, there is no
	// single argument word to read the directory back out of at the flag,
	// and the env-var form is not even in Args — see CallExpr.Assigns).
	GitDirAmbiguous bool
}

// ParseResult is the outcome of splitting a command into segments, mirroring
// the bash guard's segs(): one entry per simple command at command position
// (pipeline/;/&&/||/& members, subshells, $(...) and backtick bodies, and the
// recursively-parsed bodies of `shell -c '...'` invocations, wherever in the
// command line they occur — behind env/timeout/nohup/nice/xargs/find -exec/
// exec/command/ssh, or bare). Heredoc bodies are never turned into segments —
// they are data, not commands — even though the raw command text (used by
// has()) still contains them verbatim.
type ParseResult struct {
	Segments []Segment
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
	return parseCommandDepth(cmd, 0)
}

// parseCommandDepth is parseCommand with an explicit shell-c nesting depth,
// threaded through so maxShellCDepth actually bounds recursion (a top-level
// call to parseCommand always starts at 0; expandShellC below is the only
// other caller, and it passes depth+1).
func parseCommandDepth(cmd string, depth int) ParseResult {
	if depth < maxShellCDepth && exceedsSubstNesting(cmd, maxSubstNesting) {
		return ParseResult{Segments: fallbackSegments(cmd, depth), Fallback: true}
	}
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	f, err := parser.Parse(strings.NewReader(cmd), "")
	if err != nil || f == nil {
		// NOTE: no RecoverErrors here on purpose. It used to let the parser
		// swallow an unparsed tail silently (err == nil, the bad statement
		// just missing from f.Stmts) instead of routing to the fallback,
		// which is the one path guaranteed to still run has()/at() on the
		// raw text. A real syntax error must always reach the fallback.
		return ParseResult{Segments: fallbackSegments(cmd, depth), Fallback: true}
	}
	src := []byte(cmd)
	return ParseResult{Segments: collectSegments(src, f, depth)}
}

// exceedsSubstNesting is a rough, quote-unaware scan for "$(" nesting beyond
// limit. It over-triggers on quoted/escaped "$(" text, which is fine: this
// only ever pushes a command onto the (still-safe) fallback path early.
func exceedsSubstNesting(cmd string, limit int) bool {
	depth := 0
	for i := 0; i < len(cmd); i++ {
		switch {
		case cmd[i] == '$' && i+1 < len(cmd) && cmd[i+1] == '(':
			depth++
			if depth > limit {
				return true
			}
			i++
		case cmd[i] == ')' && depth > 0:
			depth--
		}
	}
	return false
}

// fallbackSplit is the dumb, quote-unaware split used only when the real
// parser rejects the command outright (unbalanced quotes, unclosed heredoc,
// zsh-only syntax the Bash tool runs directly — inputs a model does sometimes
// produce). It mirrors the separator set the bash splitter uses at the
// character level: ; | & ( ) and backtick.
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

// reFallbackShellC finds `[/path/]shell [flags] -c BODY` anywhere in raw
// text, the same shape bash's SHELLC_RE matches with grep -Eo — used only on
// the fallback path, where there is no AST to walk. Body is the last capture
// group (quoted or a single bare word).
var reFallbackShellC = regexp.MustCompile(`(^|[[:space:]])([^[:space:]]*/)?(zsh|bash|sh|dash|ksh)([[:space:]]+(-o[[:space:]]+[^[:space:]]+|--[a-z][a-z-]*|-[a-zA-Z]+))*[[:space:]]+-[a-zA-Z]*c[[:space:]]+("[^"]*"|'[^']*'|[^[:space:]]+)`)

// reFallbackGitCDir extracts a `-C <dir>` occurrence from a fallback
// segment's raw text, the same way the bash guard's push/commit rules do
// (`grep -Eo -- '-C[[:space:]]*[^[:space:]]+' <<<"$seg" | head -1`): there is
// no AST on the fallback path, so -C cannot be resolved structurally the way
// gitDashCFlag does for a parsed segment, and a regex over the text is
// exactly what bash itself falls back to.
var reFallbackGitCDir = regexp.MustCompile(`-C[[:space:]]*([^[:space:]]+)`)

// reFallbackGitAmbiguous is the fallback-path (text-only) equivalent of the
// --git-dir/--work-tree half of gitDashCFlag's ambiguous return — there is
// no AST to scan structurally here, so a regex over the raw segment text is
// what the bash guard itself falls back to as well. It does not catch the
// GIT_DIR=/GIT_WORK_TREE= env-assignment form (fallbackGitHead requires the
// segment's own first field to be "git", which an env-prefixed invocation
// never is); that form reaching the fallback path at all requires pairing it
// with something else mvdan/sh cannot parse, which is not a shape any known
// caller produces.
var reFallbackGitAmbiguous = regexp.MustCompile(`(^|[[:space:]])--(git-dir|work-tree)([[:space:]]|=)`)

// fallbackGitHead reports whether t's first word (by basename) is "git" —
// the fallback-path equivalent of isGitInvocation, which has no AST to walk.
func fallbackGitHead(t string) bool {
	fields := strings.Fields(t)
	return len(fields) > 0 && basename(fields[0]) == "git"
}

// fallbackSegments is fallbackSplit plus, for every `shell -c BODY` found
// anywhere in the raw text, BODY's own fallback-split segments (recursively,
// since BODY can itself contain another `shell -c ...`). Without this, the
// fallback path — reached whenever mvdan/sh cannot parse the command at all —
// would never look inside a -c body, unlike bash's shellc_bodies, which
// always runs on raw text regardless of what else parses.
//
// Every git-headed segment also gets GitCDir/HasGitCDir filled in from its
// own text via reFallbackGitCDir. Without this, a command mvdan/sh cannot
// parse (a zsh glob qualifier like `*(N)`, an unbalanced quote) silently lost
// its `git -C <dir>` entirely: pushNeedsConfirm and commitTargetDir fell back
// to the hook's own cwd and ignored the real target directory, turning a
// bash deny/ask into a Go allow.
func fallbackSegments(cmd string, depth int) []Segment {
	texts := fallbackSplit(cmd)
	texts = append(texts, fallbackShellCBodies(cmd, depth)...)
	segs := make([]Segment, len(texts))
	for i, t := range texts {
		seg := Segment{Text: t}
		if fallbackGitHead(t) {
			if m := reFallbackGitCDir.FindStringSubmatch(t); m != nil {
				seg.GitCDir, seg.HasGitCDir = m[1], true
			}
			seg.GitDirAmbiguous = reFallbackGitAmbiguous.MatchString(t)
		}
		segs[i] = seg
	}
	return segs
}

func fallbackShellCBodies(cmd string, depth int) []string {
	if depth >= maxShellCDepth {
		return nil
	}
	var out []string
	for _, m := range reFallbackShellC.FindAllStringSubmatch(cmd, -1) {
		body := stripOuterQuotes(m[len(m)-1])
		if body == "" {
			continue
		}
		out = append(out, fallbackSplit(body)...)
		out = append(out, fallbackShellCBodies(body, depth+1)...)
	}
	return out
}

// heredocShellCSegments finds `[/path/]shell [flags] -c BODY` anywhere in a
// heredoc body's raw text (never visited by the AST walk in collectSegments
// — see its Redirect case) via the same reFallbackShellC regex the fallback
// path uses, and recursively parses each BODY as its own script via
// parseCommandDepth — the full-fidelity treatment expandShellC gives a
// structurally-found body, rather than the fallback path's text-only split.
// Bounded by maxShellCDepth like every other -c unwind.
func heredocShellCSegments(body string, depth int) []Segment {
	if depth >= maxShellCDepth {
		return nil
	}
	var out []Segment
	for _, m := range reFallbackShellC.FindAllStringSubmatch(body, -1) {
		inner := stripOuterQuotes(m[len(m)-1])
		if inner == "" {
			continue
		}
		res := parseCommandDepth(inner, depth+1)
		out = append(out, res.Segments...)
	}
	return out
}

// collectSegments walks the whole parsed tree with syntax.Walk rather than a
// hand-enumerated type switch. A hand-enumerated switch is exactly what used
// to miss DeclClause (export/local/declare/readonly), TestClause ([[ ]]),
// ArithmCmd ((( ))), LetClause, a C-style for's Init/Cond/Post, and a
// substitution nested inside any of those (${a[$(...)]}, $(( $(...) + 1 )))
// — Walk's own type switch in the syntax package already knows how to
// recurse into every one of them, so there is nothing left to hand-list.
func collectSegments(src []byte, root syntax.Node, depth int) []Segment {
	var out []Segment
	skipHdoc := map[*syntax.Word]bool{}
	var visit func(syntax.Node) bool
	visit = func(n syntax.Node) bool {
		switch v := n.(type) {
		case *syntax.Redirect:
			if v.Hdoc != nil {
				// The heredoc BODY is data, never a segment — matching the
				// bash guard's split-vs-has asymmetry. The tag (v.Word) is
				// still walked normally, below.
				skipHdoc[v.Hdoc] = true
				// bash's shellc_bodies greps the RAW command text for a
				// `shell -c BODY` occurrence unconditionally, heredoc bodies
				// included — it has no notion of "data, not commands". The
				// AST walk here does (skipHdoc above), so a `shell -c '...'`
				// written inside a heredoc body (`ssh host <<EOF` /
				// `bash -c "git reset --hard"` / `EOF`) would otherwise never
				// be found on the successful-parse path, only on fallback.
				// Run the same raw-text pass over the body text to close
				// that gap.
				if body := rawWordText(src, v.Hdoc); body != "" {
					out = append(out, heredocShellCSegments(body, depth)...)
				}
			}
		case *syntax.Word:
			if skipHdoc[v] {
				return false
			}
		case *syntax.Stmt:
			if cmd, ok := v.Cmd.(*syntax.CallExpr); ok {
				end := cmd.End()
				for _, r := range v.Redirs {
					if re := redirEnd(r); re.Offset() > end.Offset() {
						end = re
					}
				}
				if text := offsetSlice(src, v.Pos(), end); text != "" {
					seg := Segment{Text: text}
					if isGitInvocation(src, cmd) {
						var ambiguousFlag bool
						seg.GitCDir, seg.HasGitCDir, ambiguousFlag = gitDashCFlag(src, cmd.Args)
						seg.GitDirAmbiguous = ambiguousFlag || assignsGitDirEnv(cmd.Assigns)
					}
					out = append(out, seg)
				}
				expandShellC(src, cmd, &out, depth)
			}
		}
		return true
	}
	syntax.Walk(root, visit)
	return out
}

// redirEnd is like (*syntax.Redirect).End(), except for a heredoc it stops
// right after the opening tag instead of extending through the body — the
// heredoc body is data, not part of any segment, even though the real
// Redirect.End() spans all the way to the terminator line to support
// round-tripping the source.
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

func basename(s string) string {
	if idx := strings.LastIndexByte(s, '/'); idx >= 0 {
		return s[idx+1:]
	}
	return s
}

func isGitInvocation(src []byte, cmd *syntax.CallExpr) bool {
	return len(cmd.Args) > 0 && basename(wordLiteral(src, cmd.Args[0])) == "git"
}

// gitDashCFlag scans a git invocation's own global flags (args[1:], stopping
// at the first token that is not one of them — the subcommand or anything
// else) for -C, structurally rather than by regex over the segment's text.
// It mirrors the GITPFX grammar in rules.go: -C/-c (separate or bundled),
// --git-dir/--work-tree/--namespace/--exec-path (separate or =value), -p/-P,
// and the handful of no-value long flags. Only the FIRST -C is kept, like
// the bash guard's `head -1` over its own (also structurally first) match.
// The bool result is true when the invocation carries --git-dir or
// --work-tree (separate or =value) — see Segment.GitDirAmbiguous: neither
// flag names a directory pushNeedsConfirm can read back the way -C's own
// argument word does, so their presence alone is the signal.
func gitDashCFlag(src []byte, args []*syntax.Word) (dir string, ok bool, ambiguous bool) {
	i := 1
	for i < len(args) {
		lit := wordLiteral(src, args[i])
		switch {
		case lit == "-C":
			if !ok && i+1 < len(args) {
				dir, ok = wordLiteral(src, args[i+1]), true
			}
			i += 2
		case strings.HasPrefix(lit, "-C") && len(lit) > 2:
			if !ok {
				dir, ok = lit[2:], true
			}
			i++
		case lit == "-c":
			i += 2
		case strings.HasPrefix(lit, "-c") && len(lit) > 2:
			i++
		case lit == "--git-dir" || lit == "--work-tree":
			ambiguous = true
			i += 2
		case strings.HasPrefix(lit, "--git-dir=") || strings.HasPrefix(lit, "--work-tree="):
			ambiguous = true
			i++
		case lit == "--namespace" || lit == "--exec-path":
			i += 2
		case strings.HasPrefix(lit, "--namespace=") || strings.HasPrefix(lit, "--exec-path="):
			i++
		case lit == "-p" || lit == "-P":
			i++
		case lit == "--paginate" || lit == "--no-pager" || lit == "--bare" || lit == "--literal-pathspecs" ||
			lit == "--no-optional-locks" || lit == "--no-replace-objects" || lit == "--no-lazy-fetch":
			i++
		default:
			return dir, ok, ambiguous
		}
	}
	return dir, ok, ambiguous
}

// assignsGitDirEnv reports whether a git invocation is prefixed by a
// GIT_DIR= or GIT_WORK_TREE= env-var assignment (`GIT_DIR=x git push`).
// mvdan/sh keeps these on CallExpr.Assigns, entirely separate from Args —
// cmd.Args[0] is still literally "git" either way, which is why
// isGitInvocation already sees straight through this form; only the
// directory resolution needs to know about it.
func assignsGitDirEnv(assigns []*syntax.Assign) bool {
	for _, a := range assigns {
		if a.Name == nil {
			continue
		}
		if a.Name.Value == "GIT_DIR" || a.Name.Value == "GIT_WORK_TREE" {
			return true
		}
	}
	return false
}

// expandShellC recognises `[/path/to/]shell [flags] -c BODY` (zsh, bash, sh,
// dash, ksh; flags bundled like -lc/-ec/-ic/-xc, or spelled out as --login,
// -o pipefail, etc. — the same shapes SHELLC_FLAGS in the bash guard allows)
// at ANY position among a call's arguments — not just Args[0] — and
// recursively parses BODY as its own script, folding its segments into out.
// Scanning every position is what catches `env bash -c '...'`,
// `timeout 10 sh -c "..."`, `nohup zsh -lc '...' &`, `nice -n 5 ksh -c '...'`,
// `xargs -I{} sh -c '...'`, `find . -exec bash -c '...' \;`,
// `exec bash -c '...'`, `command bash -c '...'`, `ssh host bash -c '...'` —
// bash's own shellc_bodies already gets these for free because it greps the
// raw text for the shell name with no regard for what precedes it; matching
// only Args[0] here missed every one of them.
//
// Unlike the bash guard, which extracts only one level via a single
// grep -Eo pass, this recurses fully: a nested `bash -c "zsh -c '...'"` is
// unwound all the way down (bounded by maxShellCDepth, now actually enforced
// since the depth is threaded through parseCommandDepth).
func expandShellC(src []byte, cmd *syntax.CallExpr, out *[]Segment, depth int) {
	if depth >= maxShellCDepth {
		return
	}
	for j := 0; j < len(cmd.Args); j++ {
		if !shellCNames[basename(wordLiteral(src, cmd.Args[j]))] {
			continue
		}
		body := shellCBodyAt(src, cmd.Args, j+1)
		if body == "" {
			continue
		}
		inner := parseCommandDepth(body, depth+1)
		*out = append(*out, inner.Segments...)
	}
}

// shellCBodyAt scans args[start:] for FLAGS* -c BODY (bundled or spelled
// out, as bash's SHELLC_FLAGS allows) and returns BODY's unquoted text, or ""
// if the flags never resolve to a -c invocation.
func shellCBodyAt(src []byte, args []*syntax.Word, start int) string {
	i := start
	for i < len(args) {
		lit := wordLiteral(src, args[i])
		switch {
		case lit == "-o":
			i += 2
		case reLongFlag.MatchString(lit):
			i++
		case reShortC.MatchString(lit):
			if i+1 >= len(args) {
				return ""
			}
			return stripOuterQuotes(rawWordText(src, args[i+1]))
		case reShortFlags.MatchString(lit):
			i++
		default:
			return ""
		}
	}
	return ""
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
