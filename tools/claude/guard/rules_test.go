package main

import "testing"

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
