# Global Claude Code Instructions

## Execution mode (read first)

- INTERACTIVE (main session, human present): short iterations,
  propose-and-confirm on non-trivial work — rules marked (INTERACTIVE)
  apply as written.
- DELEGATED (subagent, background job, headless -p, scheduled run): you are
  operating autonomously — the user is not watching in real time and cannot
  answer questions mid-task. For any reversible action that follows from the
  original request, proceed without asking. If unsure, make the reasonable
  assumption, state it, and keep working. Never artificially stop a task
  early for token/budget reasons; context auto-compaction is expected. Do
  not end a turn on a plan or a promise — finish with tool calls. Audit
  every status claim against an actual tool result; report outcomes
  faithfully, including failures.
- Rules marked (INTERACTIVE) do not apply in DELEGATED mode. Hard limits
  (permissions deny/ask + PreToolUse guard) apply in BOTH modes.

## General Rules

- Do NOT make unrequested changes — only change what was explicitly asked for
- (INTERACTIVE) If first approach to a code change doesn't work within 2 attempts — STOP and ask user
- For diagnostics (logs, status, ssh, network) — keep investigating autonomously, don't stop after 2 attempts
- (INTERACTIVE) Before starting non-trivial tasks: state the approach and wait for confirmation
- (INTERACTIVE) Don't try multiple alternatives silently — propose options, let user choose
- Keep suggestions minimal and practical — no extras unless explicitly requested
- (INTERACTIVE) Before executing a plan with 5+ items — show the list, get approval
- (INTERACTIVE) For documents/text: ask about target audience and focus BEFORE writing
- (INTERACTIVE) If unsure about scope or context — ask, don't guess

## Communication

- Communicate in Russian when the user writes in Russian. Code — in English.
- Do actions silently, show only results. After batch: brief summary.
- DON'T add docstrings, comments, or documentation unless explicitly asked

## Commands

- **Always execute commands yourself** via Bash when you have permission. Never suggest `! command` for the user to run if you can run it yourself.
- Execute ALL diagnostic commands yourself: ssh, logs, status checks, network tests — never ask the user to run them
- If a command fails — read the error, adjust, retry. Don't dump the error and ask user what to do.

## Workflow (INTERACTIVE)

In DELEGATED mode: skip this loop — complete the whole task end-to-end, verify, report once.

1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result: what changed, what verified
4. STOP — wait for next instruction

- If tests/linters fail — auto-fix and re-run, show only final status
- If can't fix — show error and ask for help
- For tasks affecting 5+ files — start with plan mode

## Git

- You CAN: status, diff, log, blame, add, commit, push, amend
- By default: NOT push, NOT create PRs/MRs — only when explicitly asked or as part of requested full cycle
- Commit ONLY when explicitly asked. Conventional commits. Show status after.
- For GitLab operations: always use `glab`, never `curl` or raw API calls
- For GitHub operations: always use `gh`, never `curl` or raw API calls
- Use `glab`/`gh` over MCP servers

## Agents

- Use parallel agents for multi-file review and broad codebase research
- Use background agents for tasks independent of current work
- Do NOT use agents for single-file edits, simple searches, or sequential tasks

