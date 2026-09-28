package main

import (
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// Ctx holds everything a rule needs to decide on one command: the raw text
// (for has()/at(), which must see heredoc bodies and everything else
// verbatim), the parsed segments (for seg_head/seg_with/seg_without, which
// must NOT see heredoc bodies), and the repo root used to tell a repo path
// from a scratch or system one.
type Ctx struct {
	cmd  string
	cwd  string
	segs []Segment

	cdScratchDone bool
	cdScratchVal  bool
}

// Decision is what the hook prints, or the zero value for a silent allow.
type Decision struct {
	Verdict string // "deny" or "ask"
	Reason  string
}

func deny(reason string) Decision { return Decision{"deny", reason} }
func ask(reason string) Decision  { return Decision{"ask", reason} }

var noDecision = Decision{}

// ---- cheap prefilter -------------------------------------------------------
//
// A strict superset of every word any rule below can fire on. NOTE: adding a
// rule with a new command name means adding the name here too — see the bash
// guard's own NOTE on this same regex for why the exfiltration group has no
// closing \b.
var reGated = regexp.MustCompile(`\b(terraform|kubectl|helm|nomad|docker|git|rm|sudo|chmod|ansible-playbook|python3?|node|uv|zsh|bash|sh|dash|ksh|age-keygen|cat|tee|sed|head|tail|bat|nl|less|more|echo|printf)\b|\b(curl|wget|nc|base64|xxd)|/dev/tcp|\.ssh\b|\.config/sops/age|\.env`)

// ---- mentions/has/at --------------------------------------------------------

func mentionsPattern(word string) *regexp.Regexp {
	return regexp.MustCompile(`(^|[^[:alnum:]_])(` + word + `)([^[:alnum:]_]|$)`)
}

var (
	mInfraDocker = mentionsPattern(`terraform|kubectl|helm|nomad|docker`)
	mInfraNoDoc  = mentionsPattern(`terraform|kubectl|helm|nomad`)
	mGit         = mentionsPattern(`git`)
	mSudo        = mentionsPattern(`sudo`)
	mRm          = mentionsPattern(`rm`)
	mEnvWords    = mentionsPattern(`printenv|env|set`)
	mCurlWget    = mentionsPattern(`curl|wget`)
	mFileWords   = mentionsPattern(`cat|tee|sed|echo|printf|head|tail|bat|nl|less|more`)
	mSed         = mentionsPattern(`sed`)
	mPythonNode  = mentionsPattern(`python3?|node`)
	mChmod       = mentionsPattern(`chmod`)
	mAnsible     = mentionsPattern(`ansible-playbook`)
	mCurl        = mentionsPattern(`curl`)
	mDocker      = mentionsPattern(`docker`)
	mPush        = mentionsPattern(`push`)
)

func (c *Ctx) mentions(re *regexp.Regexp) bool { return re.MatchString(c.cmd) }

// has() and at() go through grep in the bash guard, which never lets a match
// span two lines — it hands its regex engine one line at a time, full stop,
// not just a per-line ^/$. A Go (?m) flag only changes what ^/$ mean; it
// does nothing to stop a class like [^|] or [[:space:]] from consuming a
// literal \n and letting a match run from one line into the next (that
// false "environment-variable exfiltration" on an unrelated `set -e` /
// `curl` three-liner was exactly this). So both run their pattern against
// each line of cmd independently, exactly like grep, and no (?m) is needed:
// a single line's own ^/$ already mean its start/end by default.
func hasPattern(pat string) *regexp.Regexp { return regexp.MustCompile(pat) }

func matchesAnyLine(re *regexp.Regexp, text string) bool {
	for _, line := range strings.Split(text, "\n") {
		if re.MatchString(line) {
			return true
		}
	}
	return false
}

func (c *Ctx) has(re *regexp.Regexp) bool { return matchesAnyLine(re, c.cmd) }

const cp = `(^|[;&|]|&&|\|\|)[[:space:]]*`

func atPattern(pat string) *regexp.Regexp { return regexp.MustCompile(cp + pat) }

func (c *Ctx) at(re *regexp.Regexp) bool { return matchesAnyLine(re, c.cmd) }

// ---- seg_head/seg_with/seg_without ----------------------------------------

func (c *Ctx) segHead(re *regexp.Regexp) bool {
	for _, s := range c.segs {
		if re.MatchString(s.Text) {
			return true
		}
	}
	return false
}

// segWith: some segment matches head AND that same segment matches content.
func (c *Ctx) segWith(head, content *regexp.Regexp) bool {
	for _, s := range c.segs {
		if head.MatchString(s.Text) && content.MatchString(s.Text) {
			return true
		}
	}
	return false
}

// segWithout: some segment matches head but does NOT match content.
func (c *Ctx) segWithout(head, content *regexp.Regexp) bool {
	for _, s := range c.segs {
		if head.MatchString(s.Text) && !content.MatchString(s.Text) {
			return true
		}
	}
	return false
}

func segHeadRe(pat string) *regexp.Regexp { return regexp.MustCompile(`^[[:space:]]*` + pat) }

// ---- git global-flag prefix ------------------------------------------------
//
// Every git rule must tolerate global flags before the subcommand — see the
// bash guard's GITPFX for the full derivation from `git --help`.
const gitpfx = `git([[:space:]]+(-C[[:space:]]*[^[:space:]]+|-c[[:space:]]*[^[:space:]]*("[^"]*"|'[^']*')?[^[:space:]]*|--(git-dir|work-tree|namespace|exec-path)([[:space:]]+|=)[^[:space:]]+|-[pP]|--(paginate|no-pager|bare|literal-pathspecs|no-optional-locks|no-replace-objects|no-lazy-fetch)))*[[:space:]]+`

// ---- scratch / repo-path helpers -------------------------------------------

// SCRATCH_RE, tested against a single token (path, cd target, ...).
var reScratchToken = regexp.MustCompile(`^(/private)?/tmp(/|$)|CLAUDE_JOB_DIR|TMPDIR|^/var/folders/|\.claude/jobs/[^/]+/tmp(/|$)|/scratchpad(/|$)|^/dev/`)

// SCRATCH_ANY, tested against the raw command text (has()-style, multiline).
var reScratchAny = hasPattern(`(/private)?/tmp(/|$|["'])|CLAUDE_JOB_DIR|TMPDIR|/var/folders/|\.claude/jobs/[^/]+/tmp|/scratchpad`)

func (c *Ctx) isRepoPath(p string) bool {
	switch {
	case strings.HasPrefix(p, "/"):
		return strings.HasPrefix(p, c.cwd+"/")
	case strings.HasPrefix(p, "~") || strings.HasPrefix(p, "$"):
		return false
	default:
		return true
	}
}

func (c *Ctx) isScratch(p string) bool {
	if reScratchToken.MatchString(p) {
		return true
	}
	if !strings.HasPrefix(p, "/") {
		return c.cdIntoScratch()
	}
	return false
}

var reCdHead = segHeadRe(`cd[[:space:]]+`)

func (c *Ctx) cdIntoScratch() bool {
	if c.cdScratchDone {
		return c.cdScratchVal
	}
	c.cdScratchDone = true
	for _, seg := range c.segs {
		if !reCdHead.MatchString(seg.Text) {
			continue
		}
		rest := reCdHead.ReplaceAllString(seg.Text, "")
		if len(rest) > 0 && (rest[0] == '\'' || rest[0] == '"') {
			rest = rest[1:]
		}
		rest = reTrailQuoteSpace.ReplaceAllString(rest, "")
		if reScratchToken.MatchString(rest) {
			c.cdScratchVal = true
			return true
		}
	}
	return false
}

var reTrailQuoteSpace = regexp.MustCompile(`["']?[[:space:]]*$`)

// ---- cd/pushd anywhere (push-directory ambiguity) --------------------------

// ---- shell_writes_a_file ----------------------------------------------------

var (
	reCatTeeHead     = segHeadRe(`(cat|tee)\b`)
	reEchoPrintfHead = segHeadRe(`(echo|printf)\b`)
	reQuotedRedirDbl = regexp.MustCompile(`(>>?)[[:space:]]*"([^"]*)"`)
	reQuotedRedirSgl = regexp.MustCompile(`(>>?)[[:space:]]*'([^']*)'`)
	reDblQuotedSpan  = regexp.MustCompile(`"[^"]*"`)
	reSglQuotedSpan  = regexp.MustCompile(`'[^']*'`)
	reWriteTarget    = regexp.MustCompile(`(>>?[[:space:]]*|(^|[[:space:]])tee[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*)[^[:space:]<>|;&]+`)
	reWriteTargetPfx = regexp.MustCompile(`^[[:space:]]*(>>?[[:space:]]*|tee[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*)`)
)

func (c *Ctx) shellWritesAFile() bool {
	for _, seg := range c.segs {
		isCatTee := reCatTeeHead.MatchString(seg.Text) && strings.Contains(seg.Text, "<<")
		isEchoPrintf := reEchoPrintfHead.MatchString(seg.Text)
		if !isCatTee && !isEchoPrintf {
			continue
		}
		s := seg.Text
		s = reQuotedRedirDbl.ReplaceAllString(s, "$1$2")
		s = reQuotedRedirSgl.ReplaceAllString(s, "$1$2")
		s = reDblQuotedSpan.ReplaceAllString(s, "")
		s = reSglQuotedSpan.ReplaceAllString(s, "")
		for _, m := range reWriteTarget.FindAllString(s, -1) {
			t := reWriteTargetPfx.ReplaceAllString(m, "")
			if t == "" || strings.HasPrefix(t, "$") {
				continue
			}
			if !c.isScratch(t) {
				return true
			}
		}
	}
	return false
}

// ---- sed_i_on_one_file -------------------------------------------------------

var (
	reSedHead     = segHeadRe(`sed[[:space:]]`)
	reSedInPlace  = regexp.MustCompile(`(^|[[:space:]])(-[a-zA-Z]*i|--in-place)`)
	reFlagToken   = regexp.MustCompile(`(^|[[:space:]])-[^[:space:]]*`)
	reSedWordHead = segHeadRe(`sed([[:space:]]|$)`)
	reGlobChar    = regexp.MustCompile(`[*?\[]`)
)

func stripQuotedSpans(s string) string {
	s = reSglQuotedSpan.ReplaceAllString(s, "")
	s = reDblQuotedSpan.ReplaceAllString(s, "")
	return s
}

func (c *Ctx) sedIOnOneFile() bool {
	for _, seg := range c.segs {
		if !reSedHead.MatchString(seg.Text) || !reSedInPlace.MatchString(seg.Text) {
			continue
		}
		rest := stripQuotedSpans(seg.Text)
		rest = reFlagToken.ReplaceAllString(rest, "")
		rest = reSedWordHead.ReplaceAllString(rest, "")
		fields := strings.Fields(rest)
		if len(fields) != 1 {
			continue
		}
		w := fields[0]
		if reGlobChar.MatchString(w) || c.isScratch(w) || !c.isRepoPath(w) {
			continue
		}
		return true
	}
	return false
}

// ---- only_reads_repo_files ---------------------------------------------------

var (
	reTrailPipeCat = regexp.MustCompile(`\|[[:space:]]*cat([[:space:]]+-[a-zA-Z]+)*[[:space:]]*$`)
	reMidPipeCat   = regexp.MustCompile(`\|[[:space:]]*cat([[:space:]]+-[a-zA-Z]+)*[[:space:]]*(;|&&|\|\|)`)
	// The trailing [0-9]* after & (absent from the bash guard's own pattern)
	// compensates for a real parser: bash's crude splitter treats `&` as a
	// hard separator even inside `2>&1`, so `cat f 2>&1` becomes two segments
	// ("cat f 2>" and "1") there, and it is the bare "2>" that its own
	// version of this pattern strips. mvdan/sh correctly keeps `2>&1` as one
	// redirect token in one segment, so this pattern has to swallow the
	// whole thing to reach the same "no real redirect target" verdict.
	reTrailFDNoTarget = regexp.MustCompile(`[0-9]*>&?[0-9]*[[:space:]]*$`)
	reDevNullRedir    = regexp.MustCompile(`[0-9]*>[[:space:]]*/dev/(null|stderr|stdout)`)
	reTailFollow      = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*[fF]`)
	reCatSpecial      = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*[AvetT]`)
	reSedDashN        = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*n`)
	reLogExt          = regexp.MustCompile(`\.(output|log|txt)$`)
	reDigits1or2      = regexp.MustCompile(`^[0-9]{1,2}$`)
)

func stripPassthroughCat(cmd string) string {
	lines := strings.Split(cmd, "\n")
	for i, l := range lines {
		l = reTrailPipeCat.ReplaceAllString(l, "")
		l = reMidPipeCat.ReplaceAllString(l, "$2")
		lines[i] = l
	}
	return strings.Join(lines, "\n")
}

func (c *Ctx) onlyReadsRepoFiles() bool {
	if strings.Contains(stripPassthroughCat(c.cmd), "|") {
		return false
	}
	any := false
	for _, seg := range c.segs {
		if strings.TrimSpace(seg.Text) == "" {
			continue
		}
		s := reTrailFDNoTarget.ReplaceAllString(seg.Text, "")
		s = reDevNullRedir.ReplaceAllString(s, "")
		if strings.Contains(s, "<<") || strings.Contains(s, ">") {
			return false
		}
		fields := strings.Fields(s)
		if len(fields) == 0 {
			continue
		}
		head := fields[0]
		switch {
		case head == "echo" || head == "printf" || head == "cd" || head == "true" || head == ":" || reDigits1or2.MatchString(head):
			continue
		case head == "tail":
			if reTailFollow.MatchString(s) {
				return false
			}
		case head == "cat":
			if reCatSpecial.MatchString(s) {
				return false
			}
		case head == "head" || head == "bat" || head == "nl" || head == "less" || head == "more":
			// no extra check
		case head == "sed":
			if !reSedDashN.MatchString(s) {
				return false
			}
		default:
			return false
		}
		rest := stripQuotedSpans(s)
		rest = reFlagToken.ReplaceAllString(rest, "")
		restFields := strings.Fields(rest)
		if len(restFields) < 1 {
			continue
		}
		operands := restFields[1:]
		if len(operands) < 1 {
			continue
		}
		for _, f := range operands {
			if strings.HasPrefix(f, "$") || strings.HasPrefix(f, "~") {
				return false
			}
			if c.isScratch(f) {
				return false
			}
			if !c.isRepoPath(f) {
				return false
			}
			if reLogExt.MatchString(f) {
				return false
			}
		}
		any = true
	}
	return any
}

// ---- rm_has_unsafe_target -----------------------------------------------------

var (
	reRmHead       = segHeadRe(`rm\b`)
	reRmRecursive  = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*[rR]`)
	reNonFlagToken = regexp.MustCompile(`(^|[[:space:]])[^-[:space:]][^[:space:]]*`)
	reSafeRmTarget = regexp.MustCompile(`^/(private/)?tmp/|CLAUDE_JOB_DIR|/scratchpad(/|$)|(^|/)_site(/|$)|(^|/)node_modules(/|$)|(^|/)\.turbo(/|$)`)
)

func (c *Ctx) rmHasUnsafeTarget() bool {
	for _, seg := range c.segs {
		if !reRmHead.MatchString(seg.Text) || !reRmRecursive.MatchString(seg.Text) {
			continue
		}
		for _, tok := range reNonFlagToken.FindAllString(seg.Text, -1) {
			t := tok
			if len(t) > 0 && isSpaceByte(t[0]) {
				t = t[1:]
			}
			if len(t) > 0 && (t[0] == '"' || t[0] == '\'') {
				t = t[1:]
			}
			if t == "rm" {
				continue
			}
			if reSafeRmTarget.MatchString(t) {
				continue
			}
			return true
		}
	}
	return false
}

func isSpaceByte(b byte) bool {
	switch b {
	case ' ', '\t', '\n', '\v', '\f', '\r':
		return true
	}
	return false
}

// ---- curl_writes_a_file -------------------------------------------------------

var (
	reCurlOutputFlag   = regexp.MustCompile(`(^|[[:space:]])(-[a-zA-Z]*o|--output)([[:space:]]|=)*[^[:space:]]*`)
	reCurlOutputPrefix = regexp.MustCompile(`^[[:space:]]*(-[a-zA-Z]*o|--output)[[:space:]=]*`)
	reCurlSafeOutput   = regexp.MustCompile(`^(/dev/null)?$|^/(private/)?tmp/|CLAUDE_JOB_DIR|/scratchpad(/|$)`)
)

func (c *Ctx) curlWritesAFile() bool {
	for _, seg := range c.segs {
		if !reCurlBareHead.MatchString(seg.Text) {
			continue
		}
		for _, m := range reCurlOutputFlag.FindAllString(seg.Text, -1) {
			v := reCurlOutputPrefix.ReplaceAllString(m, "")
			if len(v) > 0 && (v[0] == '"' || v[0] == '\'') {
				v = v[1:]
			}
			if reCurlSafeOutput.MatchString(v) {
				continue
			}
			return true
		}
	}
	return false
}

// ---- git push --------------------------------------------------------------
//
// Pushing a feature branch is the normal end of an autonomous run, and a blanket
// ask there waited 14–118 minutes for nobody in the audited sessions. A blacklist
// of dangerous shapes kept finding bypasses (quote-splicing, wrappers, `-c`/`-C`
// tricks, GIT_DIR relocation, alias indirection...), so this is a WHITELIST
// instead: silent requires the exact bare shape (Segment.Push.Exact, computed
// structurally in parse.go), nothing anywhere else in the command that could
// hide or relocate a push (Segment.PushDisqualifier / GitDirAmbiguous / a second
// Segment.Push.Found), and a resolved target branch that is not protected.
// Everything else asks — including a command that merely LOOKS like it might
// contain a push (see mPush in evaluate's gate) but turns out, once resolved
// structurally, to hold none at all: that case returns ("", false) just like a
// clean silent push, since there was never a push to confirm in the first place.

var reProtectedBranch = regexp.MustCompile(`^(refs/heads/)?(main|master|prod|production|release(/.*)?)$`)

// reAssertForce/reAssertDelete/reAssertAllMirror back rule 5's own wording —
// "already excluded by rule 1's exact shape, but assert it": tryExactPushShape
// (parse.go) already refuses any flag beyond -u/--set-upstream and any refspec
// starting with `+` or with an empty src (`:branch`), so these can only ever
// fire on a parse.go bug, never on real input — a defensive second check, not
// the primary gate.
var (
	reAssertForce   = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)|(^|[[:space:]])--force(-with-lease(=[^[:space:]]*)?)?([[:space:]]|$)|[[:space:]]\+[^[:space:]]+`)
	reAssertDelete  = regexp.MustCompile(`(^|[[:space:]])(-d|--delete)([[:space:]]|$)|[[:space:]]:[^[:space:]]+`)
	reAssertAllMirr = regexp.MustCompile(`(^|[[:space:]])--(all|mirror)([[:space:]]|$)`)
)

// currentBranch resolves the checked-out branch of dir, "" when it cannot.
func currentBranch(dir string) string {
	out, err := exec.Command("git", "-C", dir, "symbolic-ref", "--short", "HEAD").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

const cannotTellPushTarget = "git push — could not tell the target branch, confirm?"

// ---- push whitelist gates 1–4 — checked before the whitelist logic below --
//
// Rules 1–4 close bypasses the structural shape/disqualifier checks (rules
// 1/3/5 in the original comment numbering, still enforced further down)
// cannot see at all: a command that is not really just one push, a -C
// directory resolved against the wrong cwd, local git config quietly
// changing where the push actually lands, or a destination that is not an
// ordinary branch to begin with.

// rePushWholeCmdChars/rePushWholeCmdWords/rePushLeadingDot are gate 1: the
// push must be the WHOLE command, checked textually on the raw command
// string — not structurally on the AST — because the point is exactly to
// catch anything that could put more than one thing in the command, or run
// the git invocation somewhere else, that the parser's own segmentation
// might not: a newline, a shell separator/grouping/substitution character,
// or a wrapper keyword, anywhere in the raw text.
var (
	rePushWholeCmdChars = regexp.MustCompile("[\n;&|(){}`<>#]|\\$\\(")
	rePushWholeCmdWords = regexp.MustCompile(`\b(trap|source|builtin|command|eval|exec)\b`)
	rePushLeadingDot    = regexp.MustCompile(`^[ \t]*\.([ \t]|$)`)
)

// pushCommandNotWhole is gate 1.
func pushCommandNotWhole(cmd string) bool {
	return rePushWholeCmdChars.MatchString(cmd) ||
		rePushWholeCmdWords.MatchString(cmd) ||
		rePushLeadingDot.MatchString(cmd)
}

// resolvePushDir is gate 2: a relative -C dir is resolved against the
// payload cwd (c.cwd) — the directory the command actually runs in — never
// against the hook process's own cwd, which exec.Command would otherwise
// use for a relative Dir. Every git call below (currentBranch, the config
// and ref lookups in gates 3/4) is resolved through this, not through
// shape.Dir directly.
func (c *Ctx) resolvePushDir(shape PushShape) string {
	if !shape.HasDir {
		return c.cwd
	}
	if filepath.IsAbs(shape.Dir) {
		return shape.Dir
	}
	return filepath.Join(c.cwd, shape.Dir)
}

// gitUpstream resolves dir's current branch's upstream (<remote>/<branch>),
// or "" when there is none.
func gitUpstream(dir string) string {
	out, err := exec.Command("git", "-C", dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// gitRefExists reports whether ref resolves in dir.
func gitRefExists(dir, ref string) bool {
	return exec.Command("git", "-C", dir, "show-ref", "--verify", "--quiet", ref).Run() == nil
}

// pushConfigRedirects is gate 3: local git config that could send the push
// somewhere other than what the command's own argument words say — asked of
// git directly (config can hold anything; a hand-rolled read of the config
// file would just be one more thing to keep in sync with git's own rules).
func (c *Ctx) pushConfigRedirects(dir string, shape PushShape) (string, bool) {
	if out, err := exec.Command("git", "-C", dir, "config", "--get-regexp", `^remote\..*\.push$`).Output(); err == nil && strings.TrimSpace(string(out)) != "" {
		return cannotTellPushTarget, true
	}
	if out, err := exec.Command("git", "-C", dir, "config", "push.default").Output(); err == nil {
		if v := strings.TrimSpace(string(out)); v != "" && v != "empty" && v != "simple" && v != "current" {
			return cannotTellPushTarget, true
		}
	}
	if !shape.HasRefspec {
		if u := gitUpstream(dir); u != "" {
			branch := u
			if i := strings.IndexByte(u, '/'); i >= 0 {
				branch = u[i+1:]
			}
			if reProtectedBranch.MatchString(branch) {
				return "git push to a protected branch (" + branch + ") — confirm?", true
			}
		}
	}
	return "", false
}

// pushDestNotABranch is gate 4: the destination must resolve to an ordinary
// branch — never a bare ref outside refs/heads/, an existing tag sharing the
// name, or a literal HEAD/@ used as the dst half of an explicit src:dst
// refspec (nonsensical as a push destination; HEAD/@ alone with no colon is
// the existing current-branch shorthand, left to rule 4 below).
func (c *Ctx) pushDestNotABranch(dir string, shape PushShape) bool {
	if !shape.HasRefspec {
		return false
	}
	src, dst, hasColon := shape.Refspec, shape.Refspec, false
	if i := strings.IndexByte(shape.Refspec, ':'); i >= 0 {
		src, dst, hasColon = shape.Refspec[:i], shape.Refspec[i+1:], true
	}
	if strings.HasPrefix(dst, "refs/") && !strings.HasPrefix(dst, "refs/heads/") {
		return true
	}
	if hasColon && (dst == "HEAD" || dst == "@") {
		return true
	}
	toks := map[string]bool{}
	if src != "" && !strings.HasPrefix(src, "refs/") {
		toks[src] = true
	}
	if dst != "" && !strings.HasPrefix(dst, "refs/") {
		toks[dst] = true
	}
	for tok := range toks {
		if gitRefExists(dir, "refs/tags/"+tok) {
			return true
		}
	}
	return false
}

// pushNeedsConfirm implements the push whitelist end to end: the reason to
// ask, or "" and false for a silent feature-branch push (which also covers
// "mentions git and push but there is no push here at all", see above).
func (c *Ctx) pushNeedsConfirm() (string, bool) {
	// Gate 1: the push must be the whole command — checked first and on the
	// raw text, before any structural parsing is trusted at all.
	if pushCommandNotWhole(c.cmd) {
		return cannotTellPushTarget, true
	}

	// Rule 3: cd/pushd/popd/export/declare/typeset/local/env/alias/eval/exec,
	// a GIT_DIR/GIT_WORK_TREE assignment, or a --git-dir/--work-tree flag,
	// ANYWHERE in the command — checked before anything else, so an alias
	// indirection or a relocated repo asks even when no segment on its own
	// resolves to a push candidate (see Segment.Push's own commentary).
	for _, seg := range c.segs {
		if seg.PushDisqualifier || seg.GitDirAmbiguous {
			return cannotTellPushTarget, true
		}
	}

	// Rule 3's "a second git push", plus finding the one candidate (if any)
	// rule 1 might allow silent.
	found := 0
	var shape PushShape
	var shapeSeg Segment
	for _, seg := range c.segs {
		if !seg.Push.Found {
			continue
		}
		found++
		if found == 1 {
			shape, shapeSeg = seg.Push, seg
		}
	}
	switch {
	case found == 0:
		return "", false // "git" and "push" both appear, but never as one push
	case found > 1:
		return cannotTellPushTarget, true
	case !shape.Exact:
		return cannotTellPushTarget, true
	}

	// Rule 5, asserted defensively (see the vars' own comment) — Exact
	// should already make every one of these unreachable.
	if reAssertForce.MatchString(shapeSeg.Text) {
		return "git push --force rewrites history — confirm?", true
	}
	if reAssertDelete.MatchString(shapeSeg.Text) {
		return "git push deleting a remote branch — confirm?", true
	}
	if reAssertAllMirr.MatchString(shapeSeg.Text) {
		return "git push --all/--mirror pushes every branch — confirm?", true
	}

	// Gate 2: resolve -C against the payload cwd — every git call from here
	// on (gates 3/4, and rule 4's own currentBranch below) uses this dir.
	dir := c.resolvePushDir(shape)

	// Gate 3: local git config must not redirect the push.
	if reason, need := c.pushConfigRedirects(dir, shape); need {
		return reason, true
	}

	// Gate 4: the destination must be a branch.
	if c.pushDestNotABranch(dir, shape) {
		return cannotTellPushTarget, true
	}

	// Rule 4: resolve the target branch positively.
	dst := ""
	if shape.HasRefspec {
		dst = shape.Refspec
		if i := strings.IndexByte(dst, ':'); i >= 0 {
			dst = dst[i+1:]
		}
		dst = strings.TrimPrefix(dst, "refs/heads/")
		dst = strings.TrimPrefix(dst, "heads/")
	}
	if dst == "" || dst == "HEAD" || dst == "@" {
		dst = currentBranch(dir)
	}
	if dst == "" {
		return cannotTellPushTarget, true
	}
	if reProtectedBranch.MatchString(dst) {
		return "git push to a protected branch (" + dst + ") — confirm?", true
	}
	return "", false
}

// ---- gitleaks ------------------------------------------------------------

// gitleaksAvailable is resolved once per process; exec.LookPath is cheap but
// there is no reason to call it more than once.
var gitleaksPath, gitleaksErr = exec.LookPath("gitleaks")

func gitleaksAvailable() bool { return gitleaksErr == nil }

// commitTargetDir returns the -C directory of the first `git ... commit`
// segment that HAS one — mirroring the bash guard's `grep -Eo ... | head -1`
// over every matching segment's -C occurrences, which does not stop at the
// first commit segment either: a `git commit -m a; git -C /other commit -m b`
// with the secret staged only in /other must still resolve to /other, even
// though the first commit segment has no -C of its own.
//
// -C comes from seg.GitCDir (resolved structurally from the argument words at
// parse time), never from a regex over seg.Text — a commit message built
// from `$(cat <<'EOF' ... git -C ... EOF)` puts a heredoc body inside the
// segment's own text, and a text search cannot tell that from a real flag.
func (c *Ctx) commitTargetDir() string {
	for _, seg := range c.segs {
		if reGitCommitHead.MatchString(seg.Text) && seg.HasGitCDir {
			return seg.GitCDir
		}
	}
	return ""
}

// gitleaksFlagsSecret runs `git diff --cached | gitleaks stdin` against the
// repo being committed to (not the hook's cwd — see the bash guard's NOTE on
// why that distinction matters), matching exit code 1 to "leak found". Any
// other outcome (git failure, gitleaks error) is treated as "nothing to
// block" so the hook never false-denies on infrastructure trouble.
func (c *Ctx) gitleaksFlagsSecret() bool {
	dir := c.commitTargetDir()
	gitArgs := []string{}
	if dir != "" {
		gitArgs = append(gitArgs, "-C", dir)
	}
	gitArgs = append(gitArgs, "diff", "--cached", "--no-color")
	gitCmd := exec.Command("git", gitArgs...)
	diff, err := gitCmd.Output()
	if err != nil {
		return false
	}
	gl := exec.Command(gitleaksPath, "stdin", "--no-banner", "--redact")
	gl.Stdin = strings.NewReader(string(diff))
	err = gl.Run()
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode() == 1
	}
	return false
}

// ---- interpreter block regexes ---------------------------------------------

// INTERP recognises an interpreter invocation beyond a bare leading token:
// $(...) substitution, env/nice/nohup wrappers, `uv run [--flags] python`,
// full paths. The trailing [[:space:]] (not \b) is load-bearing — see the
// bash guard's NOTE — or `fix(node): ...` in a commit subject reads as a
// node invocation.
var reInterp = hasPattern(`(^|[;&|(` + "`" + `]|&&|\|\||\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*((env|nice|nohup)[[:space:]]+|uv[[:space:]]+run[[:space:]]+([^[:space:]]+[[:space:]]+)*)*([^[:space:]]*/)?(python3?|node)[[:space:]]`)

var reInterpWrite = hasPattern(`\.write_text\(|\bopen\([^)]*,[[:space:]]*\\?["'][wa]|\bwriteFileSync\(|\bwriteFile\(`)
var reInterpShellOut = hasPattern(`os\.(system|popen|exec[lv]|spawn)|\bsubprocess\b|\bpty\.spawn\b|child_process|\b(exec|spawn|execFile)Sync\b|__import__\([^)]*(os|subprocess|pty)`)
var reInterpTreeDelete = hasPattern(`\brmtree\(|os\.removedirs|\b(rm|rmdir)Sync\([^)]*recursive|\bfs\.rm(dir)?\([^)]*recursive`)
var reInterpNetwork = hasPattern(`\b(urllib|requests|httpx|http\.client|socket|ftplib|smtplib|paramiko)\b|\bfetch\(|\baxios\b`)

// ---- ssh/age private-key block ---------------------------------------------

var reSSHAuthorizedEtc = regexp.MustCompile(`\.ssh/(authorized_keys|known_hosts|config|sockets)[^[:space:]']*`)
var reSSHPubFile = regexp.MustCompile(`\.ssh/[^[:space:]']*\.pub`)
var reSSHOrAge = hasPattern(`(\.ssh\b|\.config/sops/age|\bage-keygen\b)`)

// ---- reverse shell -----------------------------------------------------------

var reReverseShellInteractive = hasPattern(`\b(bash|sh|zsh|dash|ksh)[[:space:]]+-[a-zA-Z]*i[a-zA-Z]*\b`)
var reReverseShellDuplex = hasPattern(`(0>&1|0<&1|<>[[:space:]]*/dev/tcp/)`)

// ---- .env ---------------------------------------------------------------

var reEnvReadHead = segHeadRe(`(cat|less|more|head|tail|bat)[[:space:]]+[^|;&]*\.env(\.[[:alnum:]_-]+)?`)
var reEnvExempt = hasPattern(`\.env\.(example|sample|template|dist)`)

// ---- exfiltration ---------------------------------------------------------

var reEnvExfil = atPattern(`(printenv|env|set)\b[^|]*\|[^|]*(base64|curl|wget|nc|xxd)`)
var rePipeToShell = atPattern(`(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh)\b`)

// ---- git rules -------------------------------------------------------------

var reGitResetHard = segHeadRe(gitpfx + `reset[[:space:]]+--hard\b`)
var reGitClean = segHeadRe(gitpfx + `clean\b`)
var reGitBranchForceDelete = segHeadRe(gitpfx + `branch[[:space:]]+(-[a-zA-Z]*D|-[a-zA-Z]*(fd|df)|--delete[[:space:]]+--force|--force[[:space:]]+--delete)\b`)
var reGitDiscardAll = segHeadRe(gitpfx + `(checkout([[:space:]]+--)?|restore)[[:space:]]+\.([[:space:]]|$)`)
var reGitCommitHead = segHeadRe(gitpfx + `commit\b`)

var reGitAddHead = segHeadRe(gitpfx + `add\b`)
var reGitAddAllContent = regexp.MustCompile(`(^|[[:space:]])(-A|--all|\.)([[:space:]]|$)`)
var reGitConfigHead = segHeadRe(gitpfx + `config\b`)
var reGitConfigHooksPath = regexp.MustCompile(`hooksPath`)
var reGitBareHead = segHeadRe(`git\b`)
var reGitDashCHooksPath = regexp.MustCompile(`(^|[[:space:]])-c[[:space:]]*[^[:space:]]*hooksPath`)

// ---- infra rules -------------------------------------------------------------

var reTerraformDestroy = segHeadRe(`terraform[[:space:]]+destroy\b`)
var reTerraformStateRmMv = segHeadRe(`terraform[[:space:]]+state[[:space:]]+(rm|mv)\b`)
var reKubectlDeleteDrain = segHeadRe(`kubectl[[:space:]]+(delete|drain)\b`)
var reHelmUninstallRollback = segHeadRe(`helm[[:space:]]+(uninstall|rollback)\b`)
var reNomadStopEtc = segHeadRe(`nomad[[:space:]]+(job[[:space:]]+(stop|purge)|node[[:space:]]+drain|alloc[[:space:]]+stop)\b`)
var reDockerVolumePrune = segHeadRe(`docker[[:space:]]+volume[[:space:]]+prune\b`)

var reTerraformApply = segHeadRe(`terraform[[:space:]]+apply\b`)
var reKubectlApply = segHeadRe(`kubectl[[:space:]]+apply\b`)
var reHelmInstallUpgrade = segHeadRe(`helm[[:space:]]+(install|upgrade)\b`)
var reNomadJobRun = segHeadRe(`nomad[[:space:]]+job[[:space:]]+run\b`)

var reSudoHead = segHeadRe(`sudo\b`)
var reRmRootHome = segHeadRe(`rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*(/|~|\$HOME|/\*|~/\*|\$HOME/\*)([[:space:]]|$)`)

var reChmodHead = segHeadRe(`chmod\b`)
var reChmod777 = regexp.MustCompile(`\b777\b`)

var reAnsiblePlaybookHead = segHeadRe(`ansible-playbook\b`)
var reAnsibleCheck = regexp.MustCompile(`(^|[[:space:]])(--check|-C)([[:space:]]|$)`)

var reCurlBareHead = segHeadRe(`curl\b`)
var reCurlMutating = regexp.MustCompile(`(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]+(POST|PUT|DELETE|PATCH)|--json\b|(^|[[:space:]])(-d|--data(-raw|-binary|-urlencode)?|-F|--form|-T|--upload-file)([[:space:]]|=|@))`)

var reDockerComposeDown = segHeadRe(`docker([[:space:]]+|-)compose[[:space:]]+down\b`)
var reDockerVolumesFlag = regexp.MustCompile(`(^|[[:space:]])(-v|--volumes)([[:space:]]|$)`)
var reDockerVolumeRm = segHeadRe(`docker[[:space:]]+volume[[:space:]]+rm\b`)

var reRmRecursiveFlag = regexp.MustCompile(`(^|[[:space:]])-[a-zA-Z]*[rR][a-zA-Z]*([[:space:]]|$)`)

var reCurlDashOFlag = regexp.MustCompile(`(^|[[:space:]])(-[a-zA-Z]*O|--remote-name)([[:space:]]|$)`)

// evaluate ports pretooluse-guard.sh's rule table, in the same order, with
// the same verdicts and reason strings. It returns noDecision for a silent
// allow.
func evaluate(c *Ctx) Decision {
	// ---- DENY: destructive infrastructure (manual only) ----
	if c.mentions(mInfraDocker) {
		if c.segHead(reTerraformDestroy) {
			return deny("terraform destroy — run it manually")
		}
		if c.segHead(reTerraformStateRmMv) {
			return deny("terraform state rm/mv — manual only")
		}
		if c.segHead(reKubectlDeleteDrain) {
			return deny("kubectl delete/drain — manual only")
		}
		if c.segHead(reHelmUninstallRollback) {
			return deny("helm uninstall/rollback — manual only")
		}
		if c.segHead(reNomadStopEtc) {
			return deny("nomad stop/purge/drain — manual only")
		}
		if c.segHead(reDockerVolumePrune) {
			return deny("docker volume prune wipes unused volumes — manual only")
		}
	}

	// ---- DENY: git operations that throw work away ----
	if c.mentions(mGit) {
		if c.segHead(reGitResetHard) {
			return deny("git reset --hard discards uncommitted work — manual only")
		}
		if c.segHead(reGitClean) {
			return deny("git clean deletes untracked files — manual only")
		}
		if c.segHead(reGitBranchForceDelete) {
			return deny("git branch force-delete — manual only")
		}
		if c.segHead(reGitDiscardAll) {
			return deny("discarding all local changes — manual only")
		}
	}

	// ---- DENY: destructive system / secret exfiltration ----
	if c.mentions(mRm) && c.segHead(reRmRootHome) {
		return deny("recursive delete of / or home")
	}
	if c.mentions(mSudo) && c.segHead(reSudoHead) {
		return deny("sudo — run it manually")
	}
	if strings.Contains(c.cmd, ".env") && c.segHead(reEnvReadHead) && !c.has(reEnvExempt) {
		return deny("reading a plaintext .env file")
	}
	if c.mentions(mEnvWords) && c.at(reEnvExfil) {
		return deny("environment-variable exfiltration")
	}
	if c.mentions(mCurlWget) && c.at(rePipeToShell) {
		return deny("pipe-to-shell from network")
	}
	if strings.Contains(c.cmd, "/dev/tcp/") && (c.has(reReverseShellInteractive) || c.has(reReverseShellDuplex)) {
		return deny("reverse shell")
	}
	if strings.Contains(c.cmd, ".ssh") || strings.Contains(c.cmd, "sops/age") || strings.Contains(c.cmd, "age-keygen") {
		stripped := reSSHAuthorizedEtc.ReplaceAllString(c.cmd, "")
		stripped = reSSHPubFile.ReplaceAllString(stripped, "")
		if reSSHOrAge.MatchString(stripped) {
			return deny("touching private keys")
		}
	}

	// ---- DENY: committing a secret (staged diff scanned by gitleaks) ----
	if c.mentions(mGit) && c.segHead(reGitCommitHead) && gitleaksAvailable() {
		if c.gitleaksFlagsSecret() {
			return deny("gitleaks flagged a secret in the staged diff — review it, then commit by hand or add a .gitleaksignore entry if it is a false positive")
		}
	}

	// ---- DENY: file work that belongs to Edit / Write / Read ----
	if c.mentions(mFileWords) && c.shellWritesAFile() {
		return deny(`writing a file from the shell (heredoc, echo, printf) — Edit for a change, Write for a new file, a script for generated content; a helper script lives in $CLAUDE_JOB_DIR/tmp`)
	}
	if c.mentions(mSed) && c.sedIOnOneFile() {
		return deny("sed -i on one file is a single edit — use Edit; sed is for the same change across many files")
	}
	if c.mentions(mFileWords) && c.onlyReadsRepoFiles() {
		return deny("dumping a repo file into the context — Read with offset/limit for a known file, Grep to find what you need")
	}

	// ---- Interpreters: judge the code, not the command name ----
	if c.mentions(mPythonNode) && c.has(reInterp) {
		if c.has(reInterpWrite) && !c.has(reScratchAny) {
			return deny(`patching a file from an interpreter — that is Edit; a helper script lives in $CLAUDE_JOB_DIR/tmp and runs from there`)
		}
		if c.has(reInterpShellOut) {
			return deny("interpreter shelling out — that escapes every pattern in this guard; write the shell command directly")
		}
		if c.has(reInterpTreeDelete) {
			return deny("recursive tree delete from an interpreter")
		}
		if c.has(reInterpNetwork) {
			return ask("interpreter opening the network — confirm?")
		}
	}

	// ---- ASK: mutating infrastructure (confirm in the moment) ----
	if c.mentions(mInfraNoDoc) {
		if c.segHead(reTerraformApply) {
			return ask("terraform apply — confirm?")
		}
		if c.segHead(reKubectlApply) {
			return ask("kubectl apply — confirm?")
		}
		if c.segHead(reHelmInstallUpgrade) {
			return ask("helm install/upgrade — confirm?")
		}
		if c.segHead(reNomadJobRun) {
			return ask("nomad job run — confirm?")
		}
	}
	if c.mentions(mChmod) && c.segWith(reChmodHead, reChmod777) {
		return ask("chmod 777 — confirm?")
	}
	// The gate is deliberately broad — raw-text "git" and "push" anywhere,
	// not "a segment structurally headed by git push" — so that a wrapper,
	// a quote, a path, or an alias indirection still reaches the whitelist
	// in pushNeedsConfirm rather than silently skipping it because no
	// segment happens to start with the bare word "git". pushNeedsConfirm
	// itself resolves the false-positive case (both words present, but
	// never as one push) back to silence — see its own comment.
	if c.mentions(mGit) && c.mentions(mPush) {
		if reason, ok := c.pushNeedsConfirm(); ok {
			return ask(reason)
		}
	}

	// ---- ASK by argument, not by command name ----
	if c.mentions(mAnsible) && c.segWithout(reAnsiblePlaybookHead, reAnsibleCheck) {
		return ask("ansible-playbook without --check — confirm?")
	}
	if c.mentions(mCurl) && c.segWith(reCurlBareHead, reCurlMutating) {
		return ask("curl with a mutating method or body — confirm?")
	}
	if strings.Contains(c.cmd, "hooksPath") {
		if c.segWith(reGitConfigHead, reGitConfigHooksPath) {
			return ask("git config core.hooksPath runs arbitrary code — confirm?")
		}
		if c.segWith(reGitBareHead, reGitDashCHooksPath) {
			return ask("git -c core.hooksPath runs arbitrary code on the next git operation — confirm?")
		}
	}
	if c.mentions(mDocker) {
		if c.segWith(reDockerComposeDown, reDockerVolumesFlag) {
			return ask("docker compose down -v destroys named volumes — confirm?")
		}
		if c.segHead(reDockerVolumeRm) {
			return ask("docker volume rm destroys the volume's data — confirm?")
		}
	}
	if c.mentions(mRm) && c.segWith(reRmHead, reRmRecursiveFlag) && c.rmHasUnsafeTarget() {
		return ask("recursive rm outside scratch — confirm the target?")
	}
	if c.mentions(mCurl) {
		if c.segWith(reCurlBareHead, reCurlDashOFlag) {
			return ask("curl -O writes a file named by the server — confirm?")
		}
		if c.curlWritesAFile() {
			return ask("curl writing the response to a file — confirm the path?")
		}
	}

	// ---- ASK: broad git-add sweeps everything, incl. the private submodule ----
	if c.mentions(mGit) && c.segWith(reGitAddHead, reGitAddAllContent) {
		return ask("git add -A/./--all stages everything — prefer explicit paths?")
	}

	return noDecision
}
