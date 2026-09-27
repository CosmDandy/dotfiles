package main

import (
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
