# claude-cli

A Go port of five hot-path scripts that used to fork jq, python, awk and a
handful of `ps`/`stat`/`date` calls on every keystroke, tool call or status
tick:

| subcommand              | replaces                                       |
|--------------------------|-------------------------------------------------|
| `statusline`             | `tools/claude/statusline.sh`                    |
| `sessions [full [sid]]`  | `tools/claude/claude-sessions.py`                |
| `pane-title <pid> <cmd> <session>` | `tools/tmux/pane-title.sh`            |
| `opsctx`                 | `tools/claude/hooks/pretooluse-opsctx.sh`       |
| `bashhint`               | `tools/claude/hooks/posttooluse-bashhint.sh`    |

Same stdin/argv/env/file contract as the script it replaces, so switching a
caller over is a one-line change (see "Switching things over" below). Each
subcommand's own file carries the comments ported from its script — read
those for *why* a rule exists; this README is about the binary as a whole.

## Why one binary

The scripts themselves are cheap in isolation; the cost was process
overhead multiplied by how often they run: statusline on every render and
every 15s refresh in every live session, pane-title every tmux
status-interval tick per client, opsctx and bashhint on every Bash call.
Each fork of jq/python/awk/ps paid full process-start cost for a few
milliseconds of actual work. One Go binary means one exec, stdlib-only
(`encoding/json`, `regexp`, `os/exec` only for the handful of calls that
generally cannot be avoided — see below), decoding the same JSON directly
instead of shelling out to jq, and computing the session badge in-process
instead of forking python.

Subprocess calls that remain, on purpose, because the information genuinely
lives in another process's table and there's no other way to get it:
`ps -o ppid=` (rightMargin's bridge-process walk, only when
`~/.claude.json` actually lists a bridge), `ps -o tty=` / `ps -t tty -o
args=` (pane-title's node/claude detection). Both are unavoidable — the
kernel's process table is not exposed any other way from userspace — and
both are on cold, rare paths (no bridge, most panes aren't running `node`).

## Layout

- `main.go` — subcommand dispatch.
- `statusline.go` — the statusline: JSON payload parsing (replacing the
  script's single jq call and IFS=0x1F/`read` decoding), the context bar,
  the five-hour/weekly rate-limit deviation math (replacing the script's
  awk block), money/session aggregation, and the four column-width render
  branches.
- `sessions.go` — the session counter shared by `sessions` and by
  statusline's own badge segment (called in-process, not forked).
- `panetitle.go` — the tmux window title.
- `opsctx.go` — the ops-domain PreToolUse hook.
- `bashhint.go` — the PostToolUse(Failure) hint hook.

## Build

```sh
cd tools/claude/cli
go build -o claude-cli .
```

Or via Nix: `nix build .#claude-cli` from `platform/nix/` (`buildGoModule`;
stdlib only, so `vendorHash = null` rather than a real hash — there is no
vendor directory to hash). The package's output binary is renamed from
`cli` (buildGoModule names it after the module directory) to `claude-cli`
in a `postInstall` step, so `nix run .#claude-cli` and every other
subcommand invocation stay consistent.

## Test

Go unit tests (none yet — behaviour is covered end to end by the parity
suite below, which is the actual acceptance criterion for a *port*):

```sh
cd tools/claude/cli
go test ./...
```

The parity suite — every subcommand against the script it replaces, on
recorded/synthesized inputs, byte for byte:

```sh
bash tools/claude/cli/parity.test.sh
```

Builds the binary itself (or set `CLAUDE_CLI_BIN=/path/to/claude-cli` to
test an already-built one). Needs `go`, `jq`, `python3` (only to run the
OLD `claude-sessions.py` for comparison — production no longer needs it).
Same conventions as `pretooluse-guard.test.sh`: counters, private temp
dirs, no `set -e`.

Test seams (env vars that exist ONLY for testing — unset, behaviour is
identical to the scripts):

- `HOME` — every subcommand that touches `~/.claude/...` or `~/.claude.json`
  reads it from `$HOME`, exactly like the script/python it replaces. Point
  it at a fixture directory (`testdata/statusline/home`,
  `testdata/sessions/recorded`) instead of adding a bespoke directory flag.
- `CLAUDE_CLI_IN_CONTAINER=1|0` (pane-title) — forces `in_container()`
  without needing to fake `/proc`, `/run/.containerenv`, etc.
- `CLAUDE_CLI_PANE_TITLE_TTY`, `CLAUDE_CLI_PANE_TITLE_ARGS` (pane-title) —
  override the `ps -o tty=` / `ps -t tty -o args=` results for the
  node/claude-detection branch. The parity suite mostly avoids needing
  these by spawning a real background process and letting both
  implementations exec the real `ps` — see its "pane-title" section.

## Benchmarks

10 runs each, same invocation, this machine (measured directly via
`subprocess.run` + `perf_counter`, not through an extra shell wrapper —
that wrapper alone cost ~20ms per call and dominated the first pass):

| subcommand                          | old (ms) | new (ms) | speedup |
|--------------------------------------|---------:|---------:|--------:|
| `statusline`                          |     80.6 |      4.0 |   20.0x |
| `sessions full`                       |     19.9 |      3.1 |    6.4x |
| `pane-title`                          |     29.5 |      3.1 |    9.6x |
| `opsctx` (cold: fresh session id)     |     35.0 |      4.0 |    8.7x |
| `opsctx` (warm: already latched)      |     32.3 |      3.5 |    9.1x |
| `bashhint`                            |     23.1 |      3.1 |    7.5x |

Matches the perf-audit numbers closely where the measurement conditions
overlap (opsctx, bashhint, pane-title); statusline and sessions read lower
here than the audit's figures, consistent with the audit's own note that
its numbers were taken under load average 8-20 (~2x inflated) — the
relative speedup is what carries over, not the absolute millisecond count.

## Switching things over

Not done by writing this binary — see the dotfiles-repo-level commit that
switches `tools/claude/settings.json` (all four hooks + the statusline
command) and `tools/tmux/.tmux.conf`'s `set-titles-string`, and deletes the
five replaced scripts, once `parity.test.sh` is green. Both the tmux and
the statusline invocation are wrapped so a missing binary (e.g. before
`/nix` mounts, ~11s after login on macOS) prints nothing and exits 0 rather
than showing an error where a status line used to be — see that commit for
the exact wrapper.

## The guard subcommand — not wired in

TODO: `tools/claude/guard` is not exposed as a `claude-cli` subcommand.
It's a separate Go module (`tools/claude/guard`, its own `go.mod`), and its
logic lives entirely in `package main` (`main.go`/`parse.go`/`rules.go`) —
a `package main` cannot be imported by another package, so folding it in
here would mean either (a) splitting guard's logic into an importable
internal package, which touches guard's own files (out of scope: another
agent owns that worktree right now), or (b) shelling out to the separately
built `guard` binary from a `claude-cli guard` subcommand, which doesn't
actually save the process-start cost this binary exists to avoid — it
would just add a second exec on top. Once guard's logic is split into a
library (a decision for whoever owns that module), wiring it in here is a
five-line subcommand: parse stdin the same way, call the library, emit the
same JSON.

## Linux / devcontainer build

Not yet wired into `platform/linux/install.sh` or
`platform/nix/home/default.nix` — `claude-guard` itself isn't wired into
`home.packages` yet either (same "not done on purpose, owner decides"
status as its own README states), so there's no existing "where claude-cli
would go" slot to drop this into. The Nix package builds and runs
correctly cross-platform (`buildGoModule` targets `x86_64-linux` and
`aarch64-linux` too, in `packages.<system>.claude-cli`); it has not been
built or run on an actual Linux devcontainer in this change.
