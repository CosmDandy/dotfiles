package main

import (
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"testing"
)

func evalCmd(cmd, cwd string) Decision {
	if cwd == "" {
		cwd = "/repo"
	}
	r := parseCommand(cmd)
	return evaluate(&Ctx{cmd: cmd, cwd: cwd, segs: r.Segments})
}

func TestEvaluateEndToEnd(t *testing.T) {
	cases := []struct {
		cmd, cwd, wantVerdict string
	}{
		{"git status --short", "/repo", ""},
		{"sudo rm -rf /", "/repo", "deny"},
		{"rm -rf /repo/build", "/repo", "ask"},
		{"terraform apply", "/repo", "ask"},
		{"cat /repo/tools/build.py", "/repo", "deny"},
		{"cat /repo/tools/build.py 2>&1", "/repo", "deny"},
		{"cat /etc/hosts", "/repo", ""},
		{"sed -i 's/a/b/' /repo/tools/build.py", "/repo", "deny"},
		{"sed -i 's/a/b/' /repo/a.py /repo/b.py", "/repo", ""},
		{`echo "x" > /repo/tools/build.py`, "/repo", "deny"},
		{"echo x > /tmp/x", "/repo", ""},
	}
	for _, c := range cases {
		got := evalCmd(c.cmd, c.cwd)
		if got.Verdict != c.wantVerdict {
			t.Errorf("evaluate(%q) = %+v, want verdict %q", c.cmd, got, c.wantVerdict)
		}
	}
}

func TestIsScratchAndIsRepoPath(t *testing.T) {
	c := &Ctx{cwd: "/repo"}
	scratch := []string{"/tmp/x", "/private/tmp/x", "$CLAUDE_JOB_DIR/tmp/x", "$TMPDIR/x", "/var/folders/xx/T/x"}
	for _, p := range scratch {
		if !c.isScratch(p) {
			t.Errorf("isScratch(%q) = false, want true", p)
		}
	}
	if c.isScratch("/repo/tools/build.py") {
		t.Errorf("isScratch on a real repo path should be false")
	}
	if !c.isRepoPath("tools/build.py") {
		t.Errorf("a relative path must be treated as a repo path")
	}
	if c.isRepoPath("~/x") || c.isRepoPath("$HOME/x") {
		t.Errorf("a ~ or $ operand must never be treated as a resolvable repo path")
	}
	if !c.isRepoPath("/repo/tools/build.py") {
		t.Errorf("an absolute path under cwd must be a repo path")
	}
	if c.isRepoPath("/etc/hosts") {
		t.Errorf("a system path must not be a repo path")
	}
}

func TestCdIntoScratchMakesRelativePathsScratch(t *testing.T) {
	r := parseCommand(`cd $CLAUDE_JOB_DIR/tmp && sed -i 's/a/b/' pages.mjs`)
	c := &Ctx{cwd: "/repo", segs: r.Segments}
	if !c.isScratch("pages.mjs") {
		t.Errorf("a relative operand after `cd` into scratch must resolve as scratch")
	}
}

func TestSedIOnOneFileGlobIsNotASingleFile(t *testing.T) {
	r := parseCommand(`sed -i 's/a/b/' src/*.py`)
	c := &Ctx{cwd: "/repo", segs: r.Segments}
	if c.sedIOnOneFile() {
		t.Errorf("a glob operand must not count as exactly one file")
	}
}

func TestRmHasUnsafeTargetScratchExemptPerTarget(t *testing.T) {
	r := parseCommand(`rm -rf /tmp/x /Users/x/Documents`)
	c := &Ctx{cwd: "/repo", segs: r.Segments}
	if !c.rmHasUnsafeTarget() {
		t.Errorf("a mix of a scratch and a real target must still be flagged")
	}
}

func TestCurlWritesAFileProbeIsExempt(t *testing.T) {
	r := parseCommand(`curl -sSL -o /dev/null -w "%{http_code}" https://example.com`)
	c := &Ctx{cwd: "/repo", segs: r.Segments}
	if c.curlWritesAFile() {
		t.Errorf("a /dev/null probe must not count as a file write")
	}
}

// has()/at() must never let a match span two lines — grep hands its regex
// engine one line at a time, full stop, not just a per-line ^/$. A Go (?m)
// flag alone leaves classes like [^|] free to consume \n, so an unrelated
// three-liner (set -e on its own line, an unrelated pipe, then a bare curl)
// used to read as "environment-variable exfiltration".
func TestHasAtDoNotMatchAcrossLines(t *testing.T) {
	cmds := []string{
		"set -euo pipefail\ntar czf - src | wc -c\ncurl -s https://example.com/health",
		"set -e\necho a | grep a\nwget -q https://example.com/x -O /tmp/x",
		"env\necho hi | base64",
	}
	for _, cmd := range cmds {
		got := evalCmd(cmd, "/repo")
		if got.Verdict != "" {
			t.Errorf("evaluate(%q) = %+v, want a silent pass (no cross-line match)", cmd, got)
		}
	}
}

// setupPushTestRepo creates a repo with an initial commit on branch base and
// returns its path; used to test git symbolic-ref based branch resolution.
func setupPushTestRepo(t *testing.T, base string) string {
	t.Helper()
	dir := t.TempDir()
	run := func(args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	run("init", "-q", "-b", base)
	run("config", "user.email", "test@example.invalid")
	run("config", "user.name", "test")
	run("commit", "--allow-empty", "-q", "-m", "init")
	return dir
}

func TestPushNeedsConfirmBundledForceFlag(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	got := evalCmd("git push -fu origin feat/x", dir)
	if got.Verdict != "ask" {
		t.Errorf("git push -fu (bundled force+upstream) = %+v, want ask", got)
	}
}

func TestPushNeedsConfirmAllMirror(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	for _, cmd := range []string{"git push --all origin", "git push --mirror origin"} {
		got := evalCmd(cmd, dir)
		if got.Verdict != "ask" {
			t.Errorf("evaluate(%q) = %+v, want ask", cmd, got)
		}
	}
}

func TestPushNeedsConfirmGlobRefspec(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	got := evalCmd(`git push origin 'refs/heads/*:refs/heads/*'`, dir)
	if got.Verdict != "ask" {
		t.Errorf("glob refspec push = %+v, want ask", got)
	}
}

func TestPushNeedsConfirmAtResolvesLikeHead(t *testing.T) {
	dir := setupPushTestRepo(t, "main")
	got := evalCmd("git push origin @", dir)
	if got.Verdict != "ask" {
		t.Errorf("git push origin @ (on main) = %+v, want ask (protected branch)", got)
	}
}

// gitDashCFlag must never pick up a "-C" that only appears inside a heredoc
// body nested in some other argument (here, the commit message itself) —
// only a real global flag among the git invocation's own argument words.
func TestGitDashCFlagIgnoresTextEmbeddedInAnArgument(t *testing.T) {
	cmd := "git commit -m \"$(cat <<'EOF'\nfix(guard): honour git -C paths\nEOF\n)\""
	r := parseCommand(cmd)
	for _, seg := range r.Segments {
		if reGitCommitHead.MatchString(seg.Text) && seg.HasGitCDir {
			t.Errorf("segment %q resolved a -C flag (%q) from text that only contains it inside an argument's heredoc body", seg.Text, seg.GitCDir)
		}
	}
}

// commitTargetDir must keep looking past a commit segment with no -C of its
// own, the same way bash's grep -Eo | head -1 does over ALL matching
// segments, not just the first.
func TestCommitTargetDirSkipsSegmentsWithoutDashC(t *testing.T) {
	r := parseCommand(`git commit -m a; git -C /some/other/repo commit -m b`)
	c := &Ctx{cwd: "/repo", segs: r.Segments}
	if got := c.commitTargetDir(); got != "/some/other/repo" {
		t.Errorf("commitTargetDir() = %q, want /some/other/repo (the second commit segment's -C)", got)
	}
}

// randomAlnum mirrors the bash guard test's own ENTROPY note: gitleaks
// rejects a low-entropy or repeated-character token, so the fixture needs
// real randomness, not a fixed string.
func randomAlnum(n int) string {
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = chars[rand.Intn(len(chars))]
	}
	return string(b)
}

// setupSecretRepo is setupPushTestRepo plus a staged file holding a
// gitleaks-recognisable GitHub-token-shaped secret.
func setupSecretRepo(t *testing.T, base string) string {
	t.Helper()
	dir := setupPushTestRepo(t, base)
	content := fmt.Sprintf("token = \"ghp_%s\"\n", randomAlnum(36))
	if err := os.WriteFile(dir+"/conf.toml", []byte(content), 0o644); err != nil {
		t.Fatalf("write conf.toml: %v", err)
	}
	cmd := exec.Command("git", "add", "conf.toml")
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git add: %v\n%s", err, out)
	}
	return dir
}

// Finding 1 (Opus review): mvdan/sh cannot parse a zsh glob qualifier like
// `*(N)`, so the command falls onto fallbackSegments — which used to drop
// `git -C <dir>` entirely and resolve every git rule against the hook's own
// cwd instead. Here cwd is a clean feature-branch repo and -C points at a
// separate repo, on main, with a secret staged: honouring -C must find the
// secret there, not silently allow because cwd itself is clean.
func TestFallbackSegmentsHonourGitDashCForGitleaks(t *testing.T) {
	if !gitleaksAvailable() {
		t.Skip("gitleaks not installed")
	}
	secretRepo := setupSecretRepo(t, "main")
	featRepo := setupPushTestRepo(t, "feat/x")
	cmd := fmt.Sprintf("git -C %s commit -m x && ls src/*.py(N)", secretRepo)
	r := parseCommand(cmd)
	if !r.Fallback {
		t.Fatalf("parseCommand(%q) did not hit the fallback path (fine on its own, but this test wants to exercise it)", cmd)
	}
	got := evaluate(&Ctx{cmd: cmd, cwd: featRepo, segs: r.Segments})
	if got.Verdict != "deny" {
		t.Errorf("evaluate(%q) with cwd=%s = %+v, want deny (gitleaks secret in the -C target)", cmd, featRepo, got)
	}
}

// Same Finding 1, for the push-side rule: -C must still resolve the
// protected-branch check to the target repo (on main), not to cwd (a clean
// feature branch), even though mvdan/sh cannot parse the rest of the line.
func TestFallbackSegmentsHonourGitDashCForPush(t *testing.T) {
	mainRepo := setupPushTestRepo(t, "main")
	featRepo := setupPushTestRepo(t, "feat/x")
	cases := []string{
		fmt.Sprintf("for f in *.md(N); do :; done; git -C %s push", mainRepo),
		fmt.Sprintf(`git -C %s push && echo "it's done`, mainRepo),
	}
	for _, cmd := range cases {
		r := parseCommand(cmd)
		if !r.Fallback {
			t.Fatalf("parseCommand(%q) did not hit the fallback path", cmd)
		}
		got := evaluate(&Ctx{cmd: cmd, cwd: featRepo, segs: r.Segments})
		if got.Verdict != "ask" {
			t.Errorf("evaluate(%q) with cwd=%s = %+v, want ask (git -C %s push resolves main, protected)", cmd, featRepo, got, mainRepo)
		}
	}
}

// Finding 2 (Opus review): a Go segment spans the whole statement including
// its line continuation, so the literal "\" token from `git push \` +
// newline + `  origin` used to land in strings.Fields(rest) and get taken
// for the remote, leaving the real remote counted as a refspec — which set
// hasRef and skipped the current-branch check entirely.
func TestPushNeedsConfirmLineContinuationDoesNotSwallowRemote(t *testing.T) {
	dir := setupPushTestRepo(t, "main")
	got := evalCmd("git push \\\n  origin", dir)
	if got.Verdict != "ask" {
		t.Errorf(`evalCmd("git push \<newline>  origin") on main = %+v, want ask (protected branch)`, got)
	}
}

// Finding 3 (Opus review): the AST walk treats a heredoc body as data and
// never visits it, so a `shell -c BODY` written inside one (as opposed to
// among a call's own arguments) was never found on the successful-parse
// path — unlike bash's shellc_bodies, which greps the raw command text
// unconditionally, heredoc bodies included.
func TestHeredocBodyShellCIsEvaluatedLikeBash(t *testing.T) {
	cmd := "ssh host <<EOF\nbash -c \"git reset --hard\"\nEOF"
	r := parseCommand(cmd)
	if r.Fallback {
		t.Fatalf("parseCommand(%q) unexpectedly hit the fallback path; this test wants the successful-parse path", cmd)
	}
	got := evaluate(&Ctx{cmd: cmd, cwd: "/repo", segs: r.Segments})
	if got.Verdict != "deny" {
		t.Errorf("evaluate(%q) = %+v, want deny (git reset --hard inside a heredoc-carried shell -c)", cmd, got)
	}
}

// Minor note (Opus review): rePushAfter/rest used to start at the FIRST bare
// " push " in the text, which is -C's own argument value here, not the real
// push subcommand. Anchoring on the structurally-found reGitPush match
// instead (mirroring bash's greedy sed, which takes the LAST " push ")
// leaves "origin" as the only token, so it is the remote — not a refspec —
// and the current-branch check (which asks, since "push" is not a resolvable
// directory) still runs.
func TestPushRestAnchorsOnStructuralSubcommandNotDashCArgument(t *testing.T) {
	got := evalCmd("git -C push push origin", "/repo")
	if got.Verdict != "ask" {
		t.Errorf(`evalCmd("git -C push push origin") = %+v, want ask (rest must start after the real push subcommand)`, got)
	}
}

// ---- Final review (post-relaxation): a push must be silent ONLY when the
// target branch is positively known — anything the guard cannot resolve
// asks, with "could not tell the target branch" as the reason. ----

// Finding 1: the target repo used to be resolved only from -C or cwd. A
// `cd`/`pushd` elsewhere in the same command changes the directory a
// `-C`-less push actually runs in, and this guard cannot follow it — cwd is
// a clean feature-branch repo, mainRepo is on main, and the push in both
// cases actually runs against mainRepo.
func TestPushCdOrPushdElsewhereAsksNotResolvesAgainstCwd(t *testing.T) {
	mainRepo := setupPushTestRepo(t, "main")
	featRepo := setupPushTestRepo(t, "feat/x")
	cases := []string{
		fmt.Sprintf("cd %s && git push", mainRepo),
		fmt.Sprintf("(cd %s; git push -u origin HEAD)", mainRepo),
	}
	for _, cmd := range cases {
		got := evalCmd(cmd, featRepo)
		if got.Verdict != "ask" {
			t.Errorf("evaluate(%q) with cwd=%s = %+v, want ask (cd/pushd elsewhere makes the target unresolvable)", cmd, featRepo, got)
		}
	}
}

// Finding 1: --git-dir/--work-tree relocate the repo the same way -C does,
// but name no single argument word pushNeedsConfirm can read a directory
// back out of the way GitCDir does for -C; the old code fell back to cwd
// (a clean feature branch) and silently allowed a push that actually landed
// on mainRepo's main.
func TestPushGitDirWorkTreeFlagsAsk(t *testing.T) {
	mainRepo := setupPushTestRepo(t, "main")
	featRepo := setupPushTestRepo(t, "feat/x")
	cmd := fmt.Sprintf("git --git-dir=%s/.git --work-tree=%s push", mainRepo, mainRepo)
	got := evalCmd(cmd, featRepo)
	if got.Verdict != "ask" {
		t.Errorf("evaluate(%q) with cwd=%s = %+v, want ask (--git-dir/--work-tree unresolvable)", cmd, featRepo, got)
	}
}

// Finding 1: GIT_DIR=/GIT_WORK_TREE= is an env-var assignment, not an
// argument word — it lives on CallExpr.Assigns, not Args, and reGitPush
// (anchored at the segment start) never even matched a segment starting
// with the assignment instead of a literal "git", so the whole push gate
// used to never fire for this shape at all.
func TestPushGitDirEnvAssignAsk(t *testing.T) {
	mainRepo := setupPushTestRepo(t, "main")
	featRepo := setupPushTestRepo(t, "feat/x")
	cmd := fmt.Sprintf("GIT_DIR=%s/.git git push", mainRepo)
	got := evalCmd(cmd, featRepo)
	if got.Verdict != "ask" {
		t.Errorf("evaluate(%q) with cwd=%s = %+v, want ask (GIT_DIR= env assignment unresolvable)", cmd, featRepo, got)
	}
}

// Finding 2: --force/--delete/a glob refspec/a protected target landing on
// the CONTINUATION line of a `git push \` + newline still has to ask on a
// feature branch, not just happen to ask because bash's per-line reader
// resolves the (wrongly-swallowed) current branch and it happens to be
// protected. Go already puts the whole statement in one segment; the fix is
// stripping the "\\\n" token before strings.Fields so the real remote/ref
// tokens are still recognised as such (see pushNeedsConfirm's own comment).
func TestPushLineContinuationFlagsOnContinuationLineAsk(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	cases := []string{
		"git push \\\n--force origin feat/x",
		"git push origin \\\n+feat/x",
		"git push origin \\\n--delete feat/y",
		"git push origin \\\nmain",
		"git push origin \\\nfeat/x:main",
	}
	for _, cmd := range cases {
		got := evalCmd(cmd, dir)
		if got.Verdict != "ask" {
			t.Errorf("evalCmd(%q) on feat/x = %+v, want ask", cmd, got)
		}
	}
}

// Finding 3: a remote or refspec token built from a variable or a command
// substitution is not the literal branch name it looks like, so the
// protected-branch regex can never match it — silently trusting the raw
// text let `$b`/`${T:-main}`/backtick/`$(...)` sail past the check entirely.
func TestPushDynamicRemoteOrRefspecTokenAsk(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	cases := []string{
		"b=main; git push origin $b",
		"git push origin HEAD:${T:-main}",
		"git push origin `echo main`",
		`git push origin "$(git rev-parse --abbrev-ref origin/HEAD | cut -d/ -f2)"`,
	}
	for _, cmd := range cases {
		got := evalCmd(cmd, dir)
		if got.Verdict != "ask" {
			t.Errorf("evalCmd(%q) on feat/x = %+v, want ask (dynamic remote/refspec token)", cmd, got)
		}
	}
}

// None of the above must make an ordinary, fully-resolvable feature-branch
// push start asking — the whole point of the relaxation this review is
// tightening, not undoing it.
func TestPushOrdinaryFeatureBranchStillSilent(t *testing.T) {
	dir := setupPushTestRepo(t, "feat/x")
	cases := []string{
		"git push -u origin feat/x",
		"git push",
	}
	for _, cmd := range cases {
		got := evalCmd(cmd, dir)
		if got.Verdict != "" {
			t.Errorf("evalCmd(%q) on feat/x = %+v, want silent pass", cmd, got)
		}
	}
	if got := evalCmd(fmt.Sprintf("git -C %s push", dir), "/some/other/cwd"); got.Verdict != "" {
		t.Errorf("git -C <featrepo> push = %+v, want silent pass", got)
	}
}
