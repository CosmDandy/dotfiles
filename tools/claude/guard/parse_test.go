package main

import (
	"strings"
	"testing"
)

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
		if !sameSet(got.Segments, c.want) {
			t.Errorf("parseCommand(%q) = %#v, want %#v", c.cmd, got.Segments, c.want)
		}
	}
}

func TestParseCommandHeredocBodyIsNotASegment(t *testing.T) {
	cmd := "cat >> /tmp/notes.md <<MD\n" + "example: echo $(sudo ls)\n" + "MD"
	got := parseCommand(cmd)
	for _, s := range got.Segments {
		if strings.Contains(s, "sudo") {
			t.Errorf("heredoc body leaked into a segment: %q (segments=%#v)", s, got.Segments)
		}
	}
}

func TestParseCommandShellCRecursion(t *testing.T) {
	got := parseCommand(`bash -c "zsh -c 'terraform destroy'"`)
	found := false
	for _, s := range got.Segments {
		if s == "terraform destroy" {
			found = true
		}
	}
	if !found {
		t.Errorf("nested shell -c body was not recursively expanded: %#v", got.Segments)
	}
}

func TestParseCommandUnclosedHeredocDoesNotSwallowTail(t *testing.T) {
	cmd := "cat <<EOF > /tmp/x\ndata\nsudo rm -rf /"
	got := parseCommand(cmd)
	t.Logf("fallback=%v segments=%#v", got.Fallback, got.Segments)
	found := false
	for _, s := range got.Segments {
		if strings.HasPrefix(strings.TrimSpace(s), "sudo") {
			found = true
		}
	}
	if !found {
		t.Errorf("unclosed heredoc swallowed the tail instead of exposing it as a segment: %#v (fallback=%v)", got.Segments, got.Fallback)
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
