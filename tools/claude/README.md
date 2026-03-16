# Claude Code Multi-Agent System for DevOps

Personal multi-agent system for DevOps workflow automation.
Lives in dotfiles, symlinked to `~/.claude/`, deployed to all environments.

## Architecture: 3 Layers

```
~/.claude/
├── CLAUDE.md              # Global instructions (<200 lines)
├── settings.json          # Permissions, hooks, model settings
├── rules/                 # Layer 1: passive, path-scoped context
│   ├── terraform.md       #   auto-loads when editing .tf files
│   ├── ansible.md         #   auto-loads for playbooks/roles
│   ├── kubernetes.md      #   auto-loads for manifests/charts
│   ├── nomad.md           #   auto-loads for .nomad files
│   ├── docker.md          #   auto-loads for Dockerfile/compose
│   └── security.md        #   always active (no paths filter)
├── agents/                # Layer 2: autonomous specialists
│   ├── infra-security.md  #   sonnet — security analysis
│   ├── tf-specialist.md   #   sonnet — Terraform expert
│   ├── ansible-specialist.md  # sonnet — Ansible expert
│   ├── k8s-specialist.md  #   sonnet — Kubernetes expert
│   ├── nomad-specialist.md    # sonnet — Nomad expert
│   └── container-lint.md  #   haiku — Dockerfile/compose linting
├── skills/                # Layer 3: user-invocable workflows
│   ├── plan/SKILL.md      #   /plan — create implementation plan
│   ├── devops-review/SKILL.md # /devops-review — orchestrated review
│   ├── security-review/SKILL.md # /security-review — security audit
│   ├── code-review/SKILL.md    # /code-review — quality analysis
│   └── implement/SKILL.md      # /implement — execute approved plan
├── agent-memory/          # Auto-created: persistent agent knowledge
│   └── <agent-name>/MEMORY.md
└── statusline.sh          # Custom status bar
```

All files in `tools/claude/` → symlinked to `~/.claude/`.

---

## Layer 1: Rules

**How they work**: rules auto-inject context when you edit matching files.
Zero token cost when not triggered.

Each rule has a `paths:` frontmatter that controls when it loads:

```yaml
---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
---
# Terraform conventions, checklists, validation commands...
```

`security.md` has no `paths:` — loads unconditionally (every session).

**When rules activate**: Claude reads/edits a file matching the glob pattern →
the rule content is injected into context automatically.

**You don't invoke rules** — they're passive. Just edit a Dockerfile and
the Docker conventions are already in context.

---

## Layer 2: Agents

**How they work**: Claude auto-delegates to agents based on their `description`.
When you say "review this Terraform code", Claude sees that `tf-specialist`'s
description matches and delegates automatically.

You can also invoke agents explicitly:
```
> Ask tf-specialist to review main.tf
> Delegate security check to infra-security
```

### Agent Memory

All agents have `memory: user` — persistent knowledge across sessions.
Stored in `~/.claude/agent-memory/<agent-name>/MEMORY.md`.

Agents remember:
- Project patterns they've seen
- Tools available in the environment
- Approved exceptions/waivers
- Recurring issues

**Reset agent memory**: delete `~/.claude/agent-memory/<agent-name>/`.

**View agent memory**: read `~/.claude/agent-memory/<agent-name>/MEMORY.md`.

### Model Routing

| Agent              | Model  | Rationale                              |
|--------------------|--------|----------------------------------------|
| infra-security     | sonnet | Complex security reasoning             |
| tf-specialist      | sonnet | IaC reasoning, state management        |
| ansible-specialist | sonnet | Idempotency analysis, module knowledge |
| k8s-specialist     | sonnet | Resource configuration, RBAC           |
| nomad-specialist   | sonnet | Job specs, update strategies           |
| container-lint     | haiku  | Checklist-driven, fast                 |

### Key Constraint

**Agents (subagents) CANNOT spawn other agents.** Only the main context
or inline skills can orchestrate multiple agents.

---

## Layer 3: Skills

Skills are user-invocable workflows. Invoke with `/<name>`:

### Available Skills

| Skill             | Invoke                           | Mode   | Can spawn agents? |
|-------------------|----------------------------------|--------|-------------------|
| /plan             | `/plan <description>`            | inline | yes               |
| /devops-review    | `/devops-review`                 | inline | yes               |
| /security-review  | `/security-review [path]`        | fork   | no (uses Explore) |
| /code-review      | `/code-review [path]`            | fork   | no (uses Explore) |
| /implement        | `/implement plans/<file>.md`     | inline | yes               |

### Execution Modes

**Inline** (no `context: fork`):
- Runs in main conversation context
- Has access to full history
- CAN spawn subagents (agents from Layer 2)
- Results stay in conversation

**Forked** (`context: fork`):
- Runs in isolated context (fresh start)
- No conversation history
- CANNOT spawn subagents
- Returns summary to main conversation
- Good for self-contained analysis

### Usage Examples

```
> /plan migrate database from PostgreSQL 14 to 16

# Claude creates plans/2026-03-16-postgres-migration.md
# Review the plan, then:

> /implement plans/2026-03-16-postgres-migration.md
```

```
> /devops-review

# Detects changed files, spawns relevant agents, aggregated report
```

```
> /security-review src/terraform/

# Isolated security audit of terraform directory
```

```
> /code-review src/api/handlers.py

# Read-only code quality analysis
```

### Skill Arguments

`$ARGUMENTS` in SKILL.md gets replaced with everything after `/skill-name`:

```
/plan refactor auth module    →  $ARGUMENTS = "refactor auth module"
/implement plans/foo.md       →  $ARGUMENTS = "plans/foo.md"
/security-review              →  $ARGUMENTS = "" (empty)
```

---

## Typical Workflows

### Plan → Review → Execute

```
1. /plan <what you want to do>
2. Review the generated plan file
3. Edit plan if needed
4. /implement plans/<file>.md
5. Review changes, commit via lazygit
```

### Pre-Commit DevOps Review

```
1. Stage your changes in lazygit
2. /devops-review
3. Fix any BLOCK/WARN findings
4. Commit
```

### Security Audit

```
1. /security-review
2. Review findings
3. Fix critical/high issues
4. /security-review (re-run to verify)
```

---

## Hooks

Configured in `settings.json`. Available events:

| Event              | Use case                                    |
|--------------------|---------------------------------------------|
| `PreToolUse`       | Block dangerous operations                  |
| `PostToolUse`      | Auto-format after edits                     |
| `SubagentStart`    | Log/notify when agent spawns                |
| `SubagentStop`     | Log/notify when agent finishes              |
| `SessionStart`     | Load project context on startup             |
| `Stop`             | Notify when Claude finishes responding      |
| `Notification`     | Desktop notifications when input needed     |

Example — auto-format after file edits:
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path' | xargs prettier --write 2>/dev/null || true"
      }]
    }]
  }
}
```

---

## UI & Agent Management

### Observing Agents

- Subagents run inline — you see their output in the main conversation
- Forked skills (`context: fork`) run in background, return summary
- Status line shows context usage (helps decide when to compact)

### Useful Commands

| Command      | What it does                              |
|--------------|-------------------------------------------|
| `/plan`      | Invoke plan skill                         |
| `/agents`    | List available agents (interactive menu)  |
| `/memory`    | Browse/edit auto-memory files             |
| `/compact`   | Manually trigger context compaction       |
| `/config`    | View current settings                     |
| `/help`      | General help                              |

### CLI

```bash
claude agents          # List all configured agents
claude skills          # List available skills (not yet documented, try it)
```

---

## Project Knowledge Storage

### The Problem

15+ repos across dev containers. Each needs project-specific context
(architecture, conventions, known issues). Auto-memory (`~/.claude/projects/`)
is machine-local and doesn't transfer between containers.

### Solution: Knowledge Repository

Create a separate private repo for project knowledge:

```
claude-knowledge/                  # separate git repo
├── README.md
├── projects/
│   ├── project-alpha/
│   │   ├── CLAUDE.md              # project-level instructions
│   │   ├── architecture.md        # key architectural decisions
│   │   ├── patterns.md            # coding patterns and conventions
│   │   └── troubleshooting.md     # known issues and fixes
│   ├── project-beta/
│   │   └── CLAUDE.md
│   └── _template/
│       └── CLAUDE.md              # template for new projects
└── shared/
    └── team-conventions.md        # shared across all projects
```

### Deployment to Dev Containers

```bash
# In dev container setup script (or Dockerfile/devcontainer.json)

# 1. Clone knowledge repo
git clone <knowledge-repo-url> ~/claude-knowledge

# 2. Symlink project-specific knowledge into the project
PROJECT="project-alpha"
ln -sf ~/claude-knowledge/projects/$PROJECT/CLAUDE.md \
       /workspace/.claude/CLAUDE.md

# 3. Optionally symlink shared knowledge as a rule
ln -sf ~/claude-knowledge/shared/team-conventions.md \
       /workspace/.claude/rules/team-conventions.md
```

### Knowledge Lifecycle

1. **Bootstrap**: create `CLAUDE.md` from template when starting new project
2. **Grow**: Claude learns → you curate important findings into knowledge files
3. **Reset**: delete project folder or specific files to start fresh
4. **Transfer**: clone repo into new dev container, symlink relevant project

### What Goes in Knowledge vs Rules

| Knowledge (per-project)            | Rules (global, in dotfiles)          |
|------------------------------------|--------------------------------------|
| Project architecture               | Terraform best practices             |
| Team conventions specific to repo  | Docker CIS benchmarks                |
| Known issues in this codebase      | Kubernetes security checklist        |
| API structure, DB schema notes     | Language-agnostic security rules     |
| Deployment specifics               | Tool validation commands             |

---

## Deployment to New Environments

### What's Needed

1. **Dotfiles** (this repo) — agents, rules, skills, settings, CLAUDE.md
2. **Knowledge repo** (optional) — per-project context

### Setup

```bash
# 1. Clone dotfiles
git clone <dotfiles-url> ~/.dotfiles

# 2. Run install script (creates symlinks)
cd ~/.dotfiles && ./install.sh

# 3. Verify
ls -la ~/.claude/agents/    # should show agent .md files
ls -la ~/.claude/rules/     # should show rule .md files
ls -la ~/.claude/skills/    # should show skill directories

# 4. (Optional) Clone knowledge repo
git clone <knowledge-url> ~/claude-knowledge
```

### Verify Everything Works

```bash
# Rules visible
ls ~/.claude/rules/*.md

# Agents visible
ls ~/.claude/agents/*.md

# Skills visible
ls ~/.claude/skills/*/SKILL.md

# CLAUDE.md under 200 lines
wc -l ~/.claude/CLAUDE.md

# Start Claude Code, try:
# /plan test the system
# /devops-review
```

---

## Maintenance

### Adding a New Domain

1. Create `rules/<domain>.md` with `paths:` frontmatter
2. Create `agents/<domain>-specialist.md` with model, memory, description
3. Update `/devops-review` SKILL.md to include the new domain in detection

### Updating Agent Expertise

Agents learn automatically via `memory: user`. To manually curate:

```bash
# View what an agent knows
cat ~/.claude/agent-memory/tf-specialist/MEMORY.md

# Edit to correct or add knowledge
nvim ~/.claude/agent-memory/tf-specialist/MEMORY.md

# Reset agent knowledge
rm -rf ~/.claude/agent-memory/tf-specialist/
```

### CLAUDE.md Budget

Current: 138 lines (budget: <200).
If adding new sections, consider moving domain-specific content to rules/ first.
