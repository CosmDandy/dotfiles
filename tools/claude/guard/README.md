# claude-guard

A Go port of `tools/claude/hooks/pretooluse-guard.sh`: the PreToolUse guard
hook for Claude Code's Bash tool. It reads the hook's JSON on stdin and
prints a permission decision on stdout (or nothing, to allow silently). Same
rules, same order, same verdicts and reason strings as the bash script — see
that file's own comments for what each rule is guarding against. The point
of the rewrite is speed: the bash version forks grep/sed/awk per rule
(60-170 ms per call, measured); this binary parses the command once with
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
go build -o guard .
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

The bash behaviour suite (290 cases) runs against either implementation via
the `GUARD_HOOK` environment variable:

```sh
# baseline, against the bash script itself
bash tools/claude/hooks/pretooluse-guard.test.sh

# against this binary
go build -o /tmp/guard-bin tools/claude/guard
GUARD_HOOK=/tmp/guard-bin bash tools/claude/hooks/pretooluse-guard.test.sh
```

Both must report `провалено: 0`.

## Switching `settings.json` over

Not done by this change on purpose — the owner does it after review. The
hook is wired in `tools/claude/settings.json` under the Bash tool's
PreToolUse hooks as:

```json
{ "type": "command", "command": "~/.dotfiles/tools/claude/hooks/pretooluse-guard.sh" }
```

To switch, point `command` at `claude-guard`: it is on PATH after
`home-manager switch` / `darwin-rebuild switch` (`packages.<system>.claude-guard`
is in `home.packages` and in the mac's `systemPackages`), or at a local
`go build -o guard .` output for a quick trial.
