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
- `parse.go` — splits a command into segments (`segs()`'s equivalent): one
  per simple command at command position, including pipelines, `;`/`&&`/`||`/`&`
  members, subshells, `$(...)`/backtick bodies, and — genuinely recursively,
  unlike the bash version's single pass — the bodies of `shell -c '...'`
  invocations. Falls back to a quote-unaware split (never a crash, never a
  silent allow) when the input does not parse at all.
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

The bash behaviour suite (258 cases) runs against either implementation via
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

To switch, point `command` at the built binary instead, e.g.
`~/.dotfiles/tools/claude/guard/guard` (build it first, or add it to the Nix
home profile once `claude-guard` is wired into `home.packages`).
