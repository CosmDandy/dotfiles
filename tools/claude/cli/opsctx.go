package main

// Port of tools/claude/hooks/pretooluse-opsctx.sh: inject ops-domain
// discipline once per session per domain.
//
// Why a hook and not just a rule: path-scoped rules fire when Claude READS a
// file. Network diagnostics, BMC work and remote administration are
// commands, not files — no glob ever matches, so the knowledge would never
// load. This keys off the command itself and points at the right skill.
//
// Emits only additionalContext, never a permissionDecision — it must not
// interfere with the PreToolUse guard, which runs alongside it.

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// commandPosition is the same anchoring pretooluse-guard.sh (and this
// script) use, so a domain word quoted inside `git commit -m "..."` does not
// trigger anything: only a word at command position — the start of the
// string or right after a `;`, `&`, `|`, `&&` or `||` separator.
//
// NOTE: no `^`/`$` multiline flag here on purpose. The original tests this
// with `grep -Eq ... <<<"$cmd"`, which matches per PHYSICAL LINE (success if
// any line matches) and never lets a match span two lines. `^` alone would
// only anchor to the whole string's start and miss a keyword at the start of
// a later line; Go's (?m) would fix that but would also let `[[:space:]]`
// elsewhere in a pattern swallow a newline and match across lines, which
// grep never does either. matchesAnyLine (below) replicates the real
// semantics: split on "\n" first, then match each line as its own string.
const commandPosition = `(^|[;&|]|&&|\|\|)[[:space:]]*`

// matchesAnyLine reports whether re matches at least one line of s, the way
// `grep -Eq pattern <<<"$s"` does: tested line by line, never as one blob.
func matchesAnyLine(re *regexp.Regexp, s string) bool {
	for _, line := range strings.Split(s, "\n") {
		if re.MatchString(line) {
			return true
		}
	}
	return false
}

var opsctxDomains = []struct {
	name string
	re   *regexp.Regexp
}{
	{"remote", regexp.MustCompile(commandPosition + `(ssh|scp|rsync|ansible|ansible-playbook)\b`)},
	{"net", regexp.MustCompile(commandPosition + `(ip|tcpdump|ss|nft|iptables|dig|getent|resolvectl|mtr|bridge)\b`)},
	{"metal", regexp.MustCompile(commandPosition + `(ipmitool|racadm|redfishtool)\b`)},
	{"vm", regexp.MustCompile(commandPosition + `(utmctl|limactl|virsh|virt-clone|virt-sysprep|qemu-img)\b`)},
}

var opsctxMessages = map[string]string{
	"remote": `Ops domain: REMOTE (ssh). Load the ops-remote skill now. Non-negotiable: BatchMode=yes + ConnectTimeout + -T so a prompt fails fast instead of eating the tool timeout; reuse one connection (ControlMaster/ControlPath/ControlPersist); anything over ~45s runs detached under tmux/systemd-run and is polled, never in the foreground — the 45s tool clock only backgrounds the local ssh client, the remote job stays tied to that channel and dies on SIGHUP if it drops; back up any remote file before editing it in place; no sudo (the guard denies it) — ask the user to run privileged steps.`,
	"net":    `Ops domain: NETWORK. Load the ops-net skill now. Non-negotiable: dump a baseline to a file first (ip -br a; ip r; ip n; ss -tulpn; nft list ruleset); read-only tools before any change; change ONE thing at a time and re-measure in the order link -> addr -> route -> neigh -> DNS -> firewall -> app; if the change touches the path you are connected through, arm a rollback BEFORE applying; check DNS with getent/resolvectl rather than dig alone; bound every capture (-nn, explicit BPF filter, -c N).`,
	"metal":  `Ops domain: BARE-METAL / BMC. Load the ops-metal skill now. Non-negotiable: prove a live console (sol info AND actual output) BEFORE any power, boot-order or BIOS change; power soft before reset/off; bootdev is one-shot unless options=persistent; never mc reset cold while the BMC is your only path in; never flash firmware over that only path; pass credentials via -E or -f, never -P.`,
	"vm":     `Ops domain: VM lifecycle. Load the ops-vm skill now. Non-negotiable: a clone is not usable until UUID, every MAC, /etc/machine-id, SSH host keys and the cloud-init instance-id are regenerated (virt-sysprep does all five); snapshot before risky changes; never boot a clone on the same L2 as its source before the MAC is changed.`,
}

type opsctxOutput struct {
	HookSpecificOutput struct {
		HookEventName     string `json:"hookEventName"`
		AdditionalContext string `json:"additionalContext"`
	} `json:"hookSpecificOutput"`
}

func runOpsctx(_ []string) {
	raw, err := io.ReadAll(os.Stdin)
	if err != nil {
		return
	}

	var in map[string]any
	if err := json.Unmarshal(raw, &in); err != nil {
		return
	}

	cmd, _ := dig(in, "tool_input", "command").(string)
	if cmd == "" {
		return
	}

	domain := ""
	for _, d := range opsctxDomains {
		if matchesAnyLine(d.re, cmd) {
			domain = d.name
		}
	}
	if domain == "" {
		return
	}

	// Everything below runs only for an actual ops command — a few per
	// session against hundreds of ordinary ones. Keeping the state
	// directory and cleanup here instead of at the top is what makes the
	// common path cheap.
	sid := "nosession"
	if v, ok := in["session_id"]; ok && v != nil {
		if s, ok := v.(string); ok {
			sid = s
		}
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	state := filepath.Join(home, ".claude", ".state", "opsctx")
	if err := os.MkdirAll(state, 0o755); err != nil {
		return
	}

	// latches are per session; drop stale ones so the directory does not
	// grow forever
	cleanupStaleLatches(state)

	latch := filepath.Join(state, sid+"."+domain)
	if _, err := os.Stat(latch); err == nil {
		return
	}
	f, err := os.OpenFile(latch, os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	f.Close()

	var out opsctxOutput
	out.HookSpecificOutput.HookEventName = "PreToolUse"
	out.HookSpecificOutput.AdditionalContext = opsctxMessages[domain]
	emitJSON(out)
}

// cleanupStaleLatches mirrors `find "$state" -type f -mtime +7 -delete`.
func cleanupStaleLatches(dir string) {
	cutoff := time.Now().Add(-7 * 24 * time.Hour)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		if info.ModTime().Before(cutoff) {
			_ = os.Remove(filepath.Join(dir, e.Name()))
		}
	}
}

// dig walks a decoded JSON map[string]any by nested keys, returning nil on
// any missing/wrong-typed step — the equivalent of jq's `.a.b // empty`.
func dig(v any, keys ...string) any {
	for _, k := range keys {
		m, ok := v.(map[string]any)
		if !ok {
			return nil
		}
		v = m[k]
	}
	return v
}

// emitJSON writes v as compact JSON with a trailing newline, matching
// `jq -nc`'s output shape byte for byte (field order comes from the struct,
// not from map key sorting).
func emitJSON(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		fmt.Fprintln(os.Stderr, "claude-cli: encoding output:", err)
	}
}
