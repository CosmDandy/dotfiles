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

```sh
cd tools/claude/cli
go test ./...
```

`cli_test.go` is one table per subcommand: the input (payload, env,
session files, state) and the exact output, 70 cases. Each case runs the
real subcommand — the test binary re-executes itself as `claude-cli` — in a
clean environment with `TZ=UTC` and a pinned clock. On a mismatch the
failure prints the new output as a Go literal; paste it into the table when
the change is intended. The bashhint hook has its own suite,
`tools/claude/hooks/posttooluse-bashhint.test.sh` (`BASHHINT_HOOK="claude-cli bashhint"`).

Test seams (env vars that exist ONLY for testing — unset, behaviour is
identical to the scripts):

- `HOME` — every subcommand that touches `~/.claude/...` or `~/.claude.json`
  reads it from `$HOME`; the tests point it at a temp dir with the case's
  session files instead of adding a bespoke directory flag.
- `CLAUDE_CLI_NOW` (statusline) — pins "now" for the rate-limit history.
- `CLAUDE_CLI_IN_CONTAINER=1|0` (pane-title) — forces `in_container()`
  without needing to fake `/proc`, `/run/.containerenv`, etc.
- `CLAUDE_CLI_PANE_TITLE_TTY`, `CLAUDE_CLI_PANE_TITLE_ARGS` (pane-title) —
  override the `ps -o tty=` / `ps -t tty -o args=` results for the
  node/claude-detection branch. The tests avoid them by spawning a real
  process and letting the binary exec the real `ps`.

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

Done: `tools/claude/settings.json` (the opsctx and bashhint hooks, and the
statusLine command) and `tools/tmux/.tmux.conf`'s `set-titles-string` all
point at `wrapper.sh <subcommand>` now, and the five replaced scripts are
gone — see the commit that made the switch for the 70/70 parity run that
gated it (71/71 after a follow-up fix added a regression case — see git
log). `wrapper.sh` execs `./claude-cli` next to itself and exits 0
silently when the binary is not there yet (e.g. before `/nix` mounts,
~11s after login on macOS, or on a fresh clone before the first `go
build`/`nix build`), so a missing binary means an empty statusline/title,
never a visible error where one used to be.

The expected outputs in `cli_test.go` come from the binary that ran that
71/71 parity.

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

## Where the binary comes from

`packages.<system>.claude-cli` in `platform/nix/flake.nix` is in the profile
on every machine: `home.packages` (`platform/nix/home/default.nix`) on Linux
and the devcontainer, `environment.systemPackages`
(`platform/nix/darwin-configuration.nix`) on the mac — handed in as the
`claudeTools` special arg. `wrapper.sh` looks next to itself first (a local
`go build -o claude-cli .`), then on PATH, and exits 0 silently when neither
exists, so a statusline never shows an error — check with
`command -v claude-cli` if it went blank. Built and run on aarch64-darwin;
the Linux package evaluates but has not been run on a devcontainer in this
change.
