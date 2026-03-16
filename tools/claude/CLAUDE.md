# Global Claude Code Instructions

## Language & Communication

- Communicate in Russian when the user writes in Russian
- Be concise and direct
- Focus on practical solutions

## Code Style

- Write clean, readable code
- Prefer simplicity over complexity
- Use meaningful variable names
- Add comments only when logic isn't self-evident

## Code Standards

**Clean Code:**
- Self-documenting code - names explain intent
- Functions do one thing well (20-30 lines)
- DRY without fanaticism - don't abstract too early

**SOLID (briefly):**
- S: one module = one reason to change
- O: extend, don't modify
- D: depend on abstractions, not concretions

**General:**
- Fail fast - errors surface early
- Fight complexity, not line count
- Explicit is better than implicit

## Tools & Preferences

- Editor: Neovim
- Shell: Zsh with zinit
- Terminal multiplexer: tmux
- Git UI: lazygit
- Package manager: Nix (cross-platform), Homebrew (macOS)

## Communication Style

**Minimal progress output:**
- DON'T write: "Reading file X", "Editing Y", "Running tests"
- Do actions silently, show only results
- After batch: brief summary of what's done and what's verified

**Auto-fix errors:**
- If tests/linters fail - fix and re-run automatically
- Show only final status, not intermediate attempts
- If can't fix - show error and ask for help

**Documentation:**
- DON'T add docstrings automatically
- DON'T add comments "for clarity"
- Add documentation ONLY when user explicitly asks

**Language:**
- Communication in Russian (when user writes in Russian)
- Code and comments (if needed) - in English

## Workflow - Small Batches

1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result: what changed, what verified
4. STOP - wait for next instruction

**DON'T:** one micro-change (too slow), entire task without stops (lose control), many unrelated changes (hard to track)

**Error handling:** auto-fix and re-run, show only final result, ask for help if stuck

## Git Workflow

**You CAN:** `git status`, `git diff`, `git log`, `git blame`, `git add`, `git commit`
**NEVER:** `git push` — user pushes himself

**Commits:** ONLY when user explicitly asks (e.g., "commit", "make a commit", "prepare commit").
Never commit on your own initiative. Use conventional commits format.
After commit — show `git status` to confirm.

## GitLab & GitHub CLI

**Priority: GitLab (work) > GitHub (personal)**
Use CLI (`glab`, `gh`) instead of MCP servers - faster, doesn't load context.

Key commands: `glab mr list/view/diff`, `glab ci status/view/trace`, `glab issue list/view`
GitHub: `gh pr list/view/diff`, `gh issue list/view`

## Python Development

**Package manager: uv (PRIORITY) > pip**

```bash
uv pip install <package>    # uv first
uv run pytest               # run via uv
uv sync                     # sync deps
```

**Tools:** ruff (lint), mypy (types), black (format)

**Code Quality:**
- Type hints mandatory - mypy strict mode
- `pathlib` instead of `os.path`
- `structlog`/`logging` - NEVER `print()` for logging
- Specific exceptions - avoid bare `except:`
- Auto-fix errors, re-run, show only final status

## DevOps & Infrastructure

Domain-specific conventions are in `rules/` (auto-loaded per file type):
- `rules/terraform.md` — Terraform (.tf, .tfvars)
- `rules/ansible.md` — Ansible (playbooks, roles, inventory)
- `rules/kubernetes.md` — Kubernetes (manifests, charts, helm)
- `rules/nomad.md` — Nomad (.nomad, .nomad.hcl)
- `rules/docker.md` — Docker (Dockerfile, compose)
- `rules/security.md` — Security (always active)

## Context Management

**Auto-compact: 75% (setting: 85%, effective ~75% with headroom buffer)**

- 0-75%: peak efficiency | 75-85%: degradation starts | 85-100%: noticeable degradation
- At 60%: think about finishing task
- At ~75%: auto-compact triggers
- Use Task agents for research, Skills for heavy operations

## Languages & Stack

**Primary:** Python (uv > pip), Shell/Bash/Nix, IaC (Docker/K8s/Nomad, Terraform/Ansible, GitLab CI/CD)
**Learning:** Go, Rust (help with examples and explanations)
