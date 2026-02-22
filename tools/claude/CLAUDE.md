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

**Examples:**

❌ **Bad (verbose):**
```
Reading file src/main.py...
Found function process_data()
Editing file...
Added error handling
Running ruff linter...
Found 3 errors
Fixing errors...
Re-running ruff...
No errors
Running tests...
Tests passed
Done!
```

✅ **Good (minimal):**
```
Added error handling to process_data().
Tests passed. DONE.
```

**Auto-fix errors:**
- If tests/linters fail - fix and re-run automatically
- Show only final status, not intermediate attempts
- If can't fix - show error and ask for help

**Documentation:**
- DON'T add docstrings automatically
- DON'T add comments "for clarity"
- Add documentation ONLY when user explicitly asks
- Exception: complex logic where comment is necessary to understand

**Language:**
- Communication in Russian (when user writes in Russian)
- Code and comments (if needed) - in English
- Brief and clear

## Workflow - Small Batches

**Work principle:**
1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result: what changed, what verified
4. STOP - wait for next instruction

**DON'T:**
- ❌ One micro-change at a time (too slow)
- ❌ Entire task without stops (lose control)
- ❌ Many unrelated changes (hard to track)

**Batch examples:**
- ✅ Add function + tests (documentation only on request)
- ✅ Fix bug + update related tests + re-run
- ✅ Refactor module + format + type check

**Error handling:**
- If tests/linters fail - auto-fix and re-run
- Show only final result (not intermediate attempts)
- If can't fix - show error and ask for help

## Git Workflow

**CRITICAL: NEVER do git commit/push/add yourself!**

User uses lazygit and makes commits himself.

**Your role:**
1. Make code changes
2. Run tests/linters
3. Show `git diff` or `git status`
4. Suggest commit message in conventional commits format:
   - `feat: add function X`
   - `fix: fix bug in Y`
   - `refactor: rework module Z`
5. STOP - wait for user to make commit himself

**You CAN use:**
- ✅ `git status` - check status
- ✅ `git diff` - check changes
- ✅ `git log` - check history
- ✅ `git blame` - check authorship

**NEVER:**
- ❌ `git commit` - user does it himself
- ❌ `git push` - user does it himself
- ❌ `git add` - user does it himself via lazygit

## GitLab & GitHub CLI

**Priority: GitLab (work) > GitHub (personal)**

**GitLab (work - PRIORITY):**
```bash
# Merge Requests
glab mr list
glab mr view <number>
glab mr diff <number>

# CI/CD
glab ci status
glab ci view <job-id>
glab ci trace <job-id>

# Issues
glab issue list
glab issue view <number>

# API
glab api /projects/:id/merge_requests
```

**GitHub (personal):**
```bash
# Pull Requests
gh pr list
gh pr view <number>
gh pr diff <number>

# Issues
gh issue list
gh issue view <number>

# API
gh api /repos/:owner/:repo/pulls
```

**IMPORTANT**: Use CLI instead of MCP servers - faster and doesn't load context.

## Python Development

**Package manager: uv (PRIORITY) > pip**

```bash
# Use uv first
uv pip install <package>
uv run pytest
uv sync

# pip as fallback
pip install <package>
```

**Tools:**
- Linter: `ruff check .`
- Type checker: `mypy src/`
- Formatter: `black .`

**Code Quality (critical):**
- Type hints mandatory - use mypy strict mode
- `pathlib` instead of `os.path`
- Use `structlog` or `logging` - NEVER `print()` for logging
- Specific exceptions - avoid bare `except:`

**Auto-fix errors:**
- If ruff/mypy/black find errors - fix automatically
- Re-run check after fixing
- Show only final status: "Fixed X errors. Check passed."

## DevOps & Infrastructure

### Ansible
- Idempotency is mandatory
- ALWAYS `ansible-playbook --check --diff` before real run
- Run `ansible-lint` before commit
- Secrets via ansible-vault only

### Kubernetes
- Resource limits/requests mandatory
- Liveness/readiness probes required
- RBAC with minimal privileges
- **Claude:** show diff before changing manifests

### Docker
- Multi-stage builds for smaller images
- NOT root user (use USER directive)
- Pin versions explicitly (never :latest in production)

### Terraform
- Remote state with locking
- **ALWAYS** `terraform plan` before apply
- **Claude:** show plan output before modifying .tf files
- Use modules for reusability

### Nomad
- Validate job files: `nomad job validate job.hcl`
- Strict HCL syntax
- Update strategies for zero-downtime deployments
- Resource constraints (CPU/memory) mandatory
- **Claude:** show plan before deploy

### CI/CD (GitLab)
- Pipeline stages: lint → test → build → deploy
- Secrets only via CI/CD variables (never hardcoded)
- Fail fast principle
- **Claude:** CI/CD errors are expensive - validate locally first

## Context Management

**Auto-compact: 70%**

Model degradation:
- 0-70%: peak efficiency, excellent reasoning
- 70-85%: degradation starts, but still good
- 85-100%: noticeable reasoning degradation

Strategy:
- At 50% in statusline - user knows it's time to think about finishing task
- At 70% - auto-compact triggers automatically
- Balance between context preservation and performance

When approaching limit:
- Use Task agents for research
- Move heavy operations to Skills
- Delegate to specialized agents

## Languages & Stack

**Primary:**
- Python (main language) - uv > pip
- Shell/Bash/Nix
- Infrastructure: Docker/Kubernetes/Nomad, Terraform/Ansible, GitLab CI/CD

**Learning:**
- Go, Rust (will have LSP servers configured)
- Help with learning via examples and explanations
