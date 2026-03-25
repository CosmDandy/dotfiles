# Global Claude Code Instructions

## General Rules

In agent mode: use best judgment within delegated scope, report findings in final response.

- Do NOT make unrequested changes — only change what was explicitly asked for
- If first approach doesn't work within 2 attempts — STOP and ask user
- Before starting non-trivial tasks: state the approach and wait for confirmation
- Don't try multiple alternatives silently — propose options, let user choose
- Keep suggestions minimal and practical — no extras unless explicitly requested
- Before executing a plan with 5+ items — show the list, get approval
- For documents/text: ask about target audience and focus BEFORE writing
- If unsure about scope or context — ask, don't guess

## Communication

- Communicate in Russian when the user writes in Russian. Code — in English.
- Do actions silently, show only results. After batch: brief summary.
- DON'T add docstrings, comments, or documentation unless explicitly asked

## Workflow

These rules apply to interactive (main session) work. Delegated agents should complete their full task autonomously.

1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result: what changed, what verified
4. STOP — wait for next instruction

- If tests/linters fail — auto-fix and re-run, show only final status
- If can't fix — show error and ask for help
- For tasks affecting 5+ files — start with plan mode

## Git

- You CAN: status, diff, log, blame, add, commit
- NEVER: `git push`
- Commit ONLY when explicitly asked. Conventional commits. Show status after.
- Use CLI (`glab`, `gh`) over MCP servers

## Agents

- Use parallel agents for multi-file review and broad codebase research
- Use background agents for tasks independent of current work
- Do NOT use agents for single-file edits, simple searches, or sequential tasks

