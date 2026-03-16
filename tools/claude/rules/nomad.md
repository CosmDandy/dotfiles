---
paths:
  - "**/*.nomad"
  - "**/*.nomad.hcl"
  - "**/nomad/**"
  - "**/jobspec/**"
---

# Nomad Conventions

## Mandatory Checks

- ALWAYS validate: `nomad job validate job.hcl`
- ALWAYS plan before deploy: `nomad job plan job.hcl`
- Show plan output to user before running
- Use `nomad job run -check-index <index> job.hcl` for safe applies

## Resource Constraints

- CPU and memory constraints are MANDATORY for all tasks
- Set realistic values based on actual usage
- Use `memory_max` for burstable memory if needed
- Network: specify `mode` and port mappings explicitly

## Update Strategy

- Define `update` stanza for zero-downtime deployments
- `max_parallel`: control rollout speed
- `health_check`: use "checks" for service-based health
- `min_healthy_time`: ensure stability before proceeding
- `auto_revert = true` for automatic rollback on failure
- `canary` deployments for critical services

## Code Structure

- Strict HCL syntax — use `nomad fmt` for formatting
- One job per file, named descriptively
- Use variables and `template` stanza for configuration
- Group related tasks in the same `group` block
- Use `service` stanza with health checks for Consul integration

## Security

- No hardcoded secrets — use Vault integration or Nomad variables
- Use `vault` stanza for dynamic secrets
- Set `user` in task config — don't run as root
- Use ACL tokens for job submission in production

## Common Mistakes

- Missing `restart` stanza (defaults may not suit your service)
- Not setting `kill_timeout` appropriately for graceful shutdown
- Forgetting `migrate` stanza for node drains
- Using `raw_exec` driver when `docker` or `exec` would work
- Not pinning Docker image versions
- Missing `check_restart` for automatic task restart on failing health checks

## Validation Commands

```bash
nomad job validate job.hcl
nomad job plan job.hcl
nomad fmt -check job.hcl
```
