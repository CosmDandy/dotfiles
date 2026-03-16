---
name: devops-review
description: Orchestrates parallel domain-specific reviews of infrastructure changes by detecting file types and spawning relevant specialist agents
---

# /devops-review — Infrastructure Code Review Orchestrator

Review infrastructure code changes by delegating to domain specialists.

## Process

### 1. Detect Changes

Run `git diff --name-only` (or `git diff --staged --name-only` if staged) to identify changed files.

Classify files into domains:
- **Terraform**: `*.tf`, `*.tfvars`
- **Ansible**: `playbooks/`, `roles/`, `inventory/`, `group_vars/`, `host_vars/`
- **Kubernetes**: `k8s/`, `manifests/`, `charts/`, `helm/`, `*deployment*`, `*service*`
- **Nomad**: `*.nomad`, `*.nomad.hcl`
- **Docker**: `Dockerfile*`, `docker-compose*`, `.dockerignore`
- **Security**: always included

### 2. Gather Context

For each domain with changes, prepare the diff context:
```bash
git diff -- <relevant-files>
```

### 3. Spawn Domain Agents

Spawn ONLY the agents relevant to detected changes, in parallel:
- Terraform changes → delegate to `tf-specialist`
- Ansible changes → delegate to `ansible-specialist`
- Kubernetes changes → delegate to `k8s-specialist`
- Nomad changes → delegate to `nomad-specialist`
- Docker changes → delegate to `container-lint`
- Always → delegate to `infra-security` (with all changed IaC files)

Pass each agent the relevant diff and file contents.

### 4. Aggregate Results

Collect all agent responses and produce a unified report:

```markdown
# DevOps Review Report

## Summary
- Files reviewed: N
- Domains: [list]
- Findings: X critical, Y high, Z medium, W low

## Findings by Domain

### Terraform (tf-specialist)
<agent findings>

### Security (infra-security)
<agent findings>

...

## Verdict: PASS / WARN / BLOCK

- **PASS**: no critical or high findings
- **WARN**: high findings exist but no critical
- **BLOCK**: critical findings — must fix before proceeding
```

### 5. Recommendations

If BLOCK or WARN:
- List specific fixes needed
- Suggest validation commands to run
- Offer to help fix issues

If PASS:
- Confirm safe to proceed
- Suggest commit message
