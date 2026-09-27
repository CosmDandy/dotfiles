package main

import (
	"strings"
	"testing"
)

func texts(segs []Segment) []string {
	out := make([]string, len(segs))
	for i, s := range segs {
		out[i] = s.Text
	}
	return out
}

func hasSegment(segs []Segment, text string) bool {
	for _, s := range segs {
		if s.Text == text {
			return true
		}
	}
	return false
}

func anySegmentHasPrefix(segs []Segment, prefix string) bool {
	for _, s := range segs {
		if strings.HasPrefix(strings.TrimSpace(s.Text), prefix) {
			return true
		}
	}
	return false
}

func anySegmentContains(segs []Segment, needle string) bool {
	for _, s := range segs {
		if strings.Contains(s.Text, needle) {
			return true
		}
	}
	return false
}

func TestParseCommandBasicSplit(t *testing.T) {
	cases := []struct {
		cmd  string
		want []string
	}{
		{"git status --short", []string{"git status --short"}},
		{"a; b && c || d", []string{"a", "b", "c", "d"}},
		{"a | b | c", []string{"a", "b", "c"}},
		{"sleep 1 & rm -rf /x", []string{"sleep 1", "rm -rf /x"}},
		{"echo $(rm -rf /x)", []string{"echo $(rm -rf /x)", "rm -rf /x"}},
		{"(rm -rf /x)", []string{"rm -rf /x"}},
	}
	for _, c := range cases {
		got := parseCommand(c.cmd)
		if !sameSet(texts(got.Segments), c.want) {
			t.Errorf("parseCommand(%q) = %#v, want %#v", c.cmd, got.Segments, c.want)
		}
	}
}

func TestParseCommandHeredocBodyIsNotASegment(t *testing.T) {
	cmd := "cat >> /tmp/notes.md <<MD\n" + "example: echo $(sudo ls)\n" + "MD"
	got := parseCommand(cmd)
	if anySegmentContains(got.Segments, "sudo") {
		t.Errorf("heredoc body leaked into a segment: %#v", got.Segments)
	}
}

func TestParseCommandShellCRecursion(t *testing.T) {
	got := parseCommand(`bash -c "zsh -c 'terraform destroy'"`)
	if !hasSegment(got.Segments, "terraform destroy") {
		t.Errorf("nested shell -c body was not recursively expanded: %#v", got.Segments)
	}
}

func TestParseCommandUnclosedHeredocDoesNotSwallowTail(t *testing.T) {
	cmd := "cat <<EOF > /tmp/x\ndata\nsudo rm -rf /"
	got := parseCommand(cmd)
	t.Logf("fallback=%v segments=%#v", got.Fallback, got.Segments)
	if !anySegmentHasPrefix(got.Segments, "sudo") {
		t.Errorf("unclosed heredoc swallowed the tail instead of exposing it as a segment: %#v (fallback=%v)", got.Segments, got.Fallback)
	}
}

// The rest of the compound-statement forms below (DeclClause, TestClause,
// ArithmCmd, LetClause, a C-style for's Init/Cond/Post, ${a[$(...)]}) are
// exactly what a hand-enumerated type switch missed and syntax.Walk does not
// — see collectSegments's doc comment. Each of these used to parse fine and
// yield zero segments for the substitution inside.
func TestParseCommandFindsSubstitutionsInEveryCompoundForm(t *testing.T) {
	cases := []struct{ name, cmd, want string }{
		{"export", `export X=$(sudo ls)`, "sudo ls"},
		{"local", `local X=$(git reset --hard)`, "git reset --hard"},
		{"declare -x", `declare -x Y="$(terraform destroy)"`, "terraform destroy"},
		{"readonly backtick", "readonly Z=`sudo id`", "sudo id"},
		{"test clause", `[[ -n $(sudo ls) ]]`, "sudo ls"},
		{"arithm cmd", `(( $(sudo id -u) == 0 ))`, "sudo id -u"},
		{"arithm exp", `echo $(( $(sudo id -u) + 1 ))`, "sudo id -u"},
		{"param index", `echo ${a[$(sudo ls)]}`, "sudo ls"},
		{"let", `let x=$(sudo id -u)`, "sudo id -u"},
		{"c-style for", `for ((i=$(sudo id -u);i<1;i++)); do :; done`, "sudo id -u"},
	}
	for _, c := range cases {
		got := parseCommand(c.cmd)
		if !hasSegment(got.Segments, c.want) {
			t.Errorf("%s: parseCommand(%q).Segments = %#v, want a %q segment", c.name, c.cmd, got.Segments, c.want)
		}
	}
}

// expandShellC used to check only Args[0], so a wrapper program ahead of the
// shell (env, timeout, nohup, nice, xargs, find -exec, exec, command, ssh)
// hid the -c body from every rule that looks at segments.
func TestParseCommandFindsShellCBehindWrappers(t *testing.T) {
	cases := []struct{ name, cmd, want string }{
		{"env", `env bash -c 'git reset --hard'`, "git reset --hard"},
		{"timeout", `timeout 10 bash -c "terraform destroy"`, "terraform destroy"},
		{"nohup", `nohup sh -c 'kubectl delete ns prod' &`, "kubectl delete ns prod"},
		{"nice", `nice -n 5 zsh -lc 'helm uninstall x'`, "helm uninstall x"},
		{"exec", `exec bash -c 'git reset --hard'`, "git reset --hard"},
		{"command", `command bash -c 'git clean -fdx'`, "git clean -fdx"},
		{"ssh", `ssh host bash -c 'git push'`, "git push"},
		{"xargs", `xargs -I{} sh -c 'rm -rf / '`, "rm -rf /"},
		{"find exec", `find . -exec bash -c 'sudo rm {}' \;`, "sudo rm {}"},
	}
	for _, c := range cases {
		got := parseCommand(c.cmd)
		if !hasSegment(got.Segments, c.want) {
			t.Errorf("%s: parseCommand(%q).Segments = %#v, want a %q segment", c.name, c.cmd, got.Segments, c.want)
		}
	}
}

// The fallback path (reached whenever mvdan/sh cannot parse the input at
// all — common with zsh-only syntax, since the Bash tool runs zsh) used to
// only quote-unaware-split the text; it never looked for a `shell -c BODY`
// inside it, unlike bash's shellc_bodies, which always runs on raw text.
func TestParseCommandFallbackStillFindsShellC(t *testing.T) {
	cases := []struct{ name, cmd, want string }{
		{"zsh array flag", `echo ${(j:,:)arr}; bash -c 'sudo ls'`, "sudo ls"},
		{"zsh glob qualifier for", `for f (*.txt) echo $f; bash -c 'git reset --hard'`, "git reset --hard"},
		{"zsh glob qualifier array", `files=(*.log(N)); bash -lc 'git reset --hard'`, "git reset --hard"},
	}
	for _, c := range cases {
		got := parseCommand(c.cmd)
		if !got.Fallback {
			t.Fatalf("%s: parseCommand(%q) did not hit the fallback path (fine on its own, but this test wants to exercise it)", c.name, c.cmd)
		}
		if !hasSegment(got.Segments, c.want) {
			t.Errorf("%s: fallback parseCommand(%q).Segments = %#v, want a %q segment", c.name, c.cmd, got.Segments, c.want)
		}
	}
}

// A real syntax error must reach the fallback, not be silently absorbed by
// error recovery (which used to leave the unparsed tail out of f.Stmts with
// err == nil, so parseCommand thought it had a clean, complete parse of
// zero segments).
func TestParseCommandUnparsableInputHitsFallback(t *testing.T) {
	got := parseCommand("echo \"unterminated\nsudo ls")
	if !got.Fallback {
		t.Fatalf("expected the fallback path for unterminated-quote input, got fallback=false segments=%#v", got.Segments)
	}
	if !anySegmentHasPrefix(got.Segments, "sudo") {
		t.Errorf("fallback segments = %#v, want a segment starting with sudo", got.Segments)
	}
}

func sameSet(got, want []string) bool {
	if len(got) != len(want) {
		return false
	}
	seen := map[string]int{}
	for _, g := range got {
		seen[g]++
	}
	for _, w := range want {
		if seen[w] == 0 {
			return false
		}
		seen[w]--
	}
	return true
}
