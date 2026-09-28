# claude-guard

The PreToolUse guard hook for Claude Code's Bash tool. It reads the hook's
JSON on stdin and prints a permission decision on stdout (or nothing, to allow
silently). It replaced the bash `tools/claude/hooks/pretooluse-guard.sh` (in
git history): same rules, same order and reason strings, verified case for
case against it before the switch; the git push decision has since been
rewritten as a whitelist that only the Go guard has. The point of the port
was speed: the bash version forked grep/sed/awk per rule (60-170 ms per call,
measured); this binary parses the command once with
[mvdan.cc/sh](https://github.com/mvdan/sh) and evaluates every rule against
compiled regexes in one process (~9 ms per call, dominated by process-start
overhead on macOS, not by the guard's own logic).

## Layout

- `main.go` — stdin JSON -> decision -> stdout JSON.
- `parse.go` — splits a command into segments (`segs()`'s equivalent) by
  walking the whole parsed tree with `syntax.Walk`, not a hand-enumerated
  type switch (a hand-enumerated one is exactly what missed `export`/`local`/
  `declare`, `[[ ]]`, `(( ))`, `let`, a C-style `for`, and a substitution
  nested inside any of them). One segment per simple command at command
  position, including pipelines, `;`/`&&`/`||`/`&` members, subshells,
  `$(...)`/backtick bodies, and — genuinely recursively, unlike the bash
  version's single `grep -Eo` pass, and at any argument position, not just
  the first (`env`, `timeout`, `nohup`, `nice`, `xargs`, `find -exec`, `exec`,
  `command`, `ssh` all hide a shell behind them) — the bodies of
  `shell -c '...'` invocations. Falls back to a quote-unaware split when the
  input does not parse at all (unbalanced quotes, or zsh-only syntax the
  Bash tool runs directly and mvdan/sh, a bash/POSIX parser, rejects); the
  fallback also extracts `shell -c '...'` bodies via the same regex bash's
  own `shellc_bodies` uses, so a `-c` payload is never missed just because
  the surrounding line does not parse. This reduces, but does not by itself
  prove, the risk of a silent allow — see the port's own PROGRESS notes for
  what is (and is not) covered.
- `rules.go` — the rule table and its helper functions, ported 1:1 from the
  bash script.

## Build

```sh
cd tools/claude/guard
go build -o claude-guard .
```

Or via Nix: `nix build .#claude-guard` from `platform/nix/` (uses
`buildGoModule`; `vendorHash` may need updating after a `go.sum` change —
`nix build` reports the correct hash on a mismatch).

## Test

Go unit tests (tokenizer edge cases, helper functions):

```sh
cd tools/claude/guard
go test ./...
```

The behaviour suite (345 cases, verdict per real command) builds the binary
itself, or takes one via `GUARD_HOOK`:

```sh
bash tools/claude/hooks/pretooluse-guard.test.sh
GUARD_HOOK=/path/to/claude-guard bash tools/claude/hooks/pretooluse-guard.test.sh
```

It must report `провалено: 0`.

## Wiring

`tools/claude/settings.json` calls `tools/claude/guard/wrapper.sh` for the Bash
tool's PreToolUse hook; the bash `pretooluse-guard.sh` it replaced is gone. The
wrapper runs `claude-guard` from next to itself (a local
`go build -o claude-guard .`) or from PATH — `packages.<system>.claude-guard` is
in `home.packages` and in the mac's `systemPackages`, so it arrives with
`home-manager switch` / `darwin-rebuild switch`.

NOTE: the wrapper fails CLOSED. With no binary it denies every Bash call with a
reason that says how to fix it — a hook that exits 127 is a non-blocking error to
Claude Code, i.e. an allow, and a missing guard must not mean an open door. On the
mac that also covers the ~11 s after login before /nix is mounted.
