---
name: security-review
description: Self-contained security analysis of infrastructure and application code checking for secrets, IAM/RBAC misconfigurations, encryption gaps, and compliance issues
context: fork
agent: Explore
---

# /security-review — Security Analysis

Perform a comprehensive security review of the current codebase or specified files: $ARGUMENTS

## Scope

If `$ARGUMENTS` specifies files/paths, review only those.
Otherwise, review the entire repository.

## Analysis Checklist

### 1. Secret Detection
- [ ] Scan all files for hardcoded secrets (passwords, API keys, tokens, private keys)
- [ ] Check environment files (.env, .env.*, env_file references)
- [ ] Review variable defaults for sensitive values
- [ ] Check git history awareness (mention if `.gitignore` misses sensitive patterns)

### 2. Access Control
- [ ] IAM policies: no wildcard `*` actions/resources
- [ ] RBAC roles: minimal privileges, no cluster-admin for apps
- [ ] Service accounts: scoped permissions
- [ ] File permissions: no world-readable secrets

### 3. Network Exposure
- [ ] No unintended `0.0.0.0/0` ingress rules
- [ ] Internal services not publicly exposed
- [ ] TLS configured for all external endpoints
- [ ] NetworkPolicies/security groups defined

### 4. Encryption
- [ ] Data at rest encryption (disks, databases, state files)
- [ ] Data in transit (TLS/mTLS between services)
- [ ] Sensitive outputs marked appropriately
- [ ] Backup encryption

### 5. Supply Chain
- [ ] Dependency versions pinned (packages, images, modules)
- [ ] Base images from trusted sources
- [ ] No known vulnerable dependencies (check if scan tools available)

### 6. Container Security (if applicable)
- [ ] Non-root user in Dockerfiles
- [ ] Minimal base images
- [ ] No unnecessary capabilities
- [ ] Read-only root filesystem where possible

## Output Format

```markdown
# Security Review Report

## Executive Summary
Overall risk: LOW / MEDIUM / HIGH / CRITICAL
Key findings: N critical, N high, N medium, N low

## Findings

### [CRITICAL] Finding title
- **File**: path:line
- **Issue**: description
- **Impact**: what could go wrong
- **Fix**: specific remediation
- **Reference**: CIS/OWASP/CVE if applicable

...

## Recommendations
Prioritized list of actions to take.
```
