# Global Claude Code Instructions

## General Rules

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

1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result: what changed, what verified
4. STOP — wait for next instruction

- If tests/linters fail — auto-fix and re-run, show only final status
- If can't fix — show error and ask for help

## Git

- You CAN: status, diff, log, blame, add, commit
- NEVER: `git push`
- Commit ONLY when explicitly asked. Conventional commits. Show status after.
- Use CLI (`glab`, `gh`) over MCP servers

## Python

- Package manager: uv > pip
- Tools: ruff (lint), mypy strict (types), black (format)
- `pathlib` over `os.path`, `logging` over `print()`, no bare `except:`

## Tools & Stack

- Neovim, Zsh, tmux, lazygit, Nix/Homebrew
- Primary: Python, Shell/Nix, IaC (Docker/K8s/Nomad, Terraform/Ansible)
- Learning: Go, Rust

## DevOps

Domain-specific rules in `rules/` (auto-loaded per file type).
