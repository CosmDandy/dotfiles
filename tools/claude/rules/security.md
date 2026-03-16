# Security Rules (Always Active)

## Secret Detection

- NEVER commit secrets, tokens, passwords, API keys
- Check for hardcoded secrets in: variables, env files, config, comments
- Patterns to flag: `password=`, `secret=`, `token=`, `api_key=`, `-----BEGIN`
- Use secret managers: Vault, AWS Secrets Manager, Doppler, sealed-secrets

## Access Control

- Least privilege principle — minimum permissions needed
- No wildcard permissions (`*`) in IAM policies, RBAC roles
- Review: who has access, what they can do, is it necessary
- Service accounts: scoped to specific resources/actions

## Network Security

- Default-deny network policies
- No `0.0.0.0/0` ingress unless explicitly public-facing
- TLS everywhere — flag unencrypted connections
- Internal services: no public exposure without load balancer/proxy

## Data Protection

- Encrypt at rest (disks, databases, state files, backups)
- Encrypt in transit (TLS/mTLS)
- Sensitive outputs marked `sensitive = true` (Terraform)
- `no_log: true` for sensitive tasks (Ansible)

## Supply Chain

- Pin dependency versions (packages, images, modules, providers)
- Verify checksums for critical downloads
- Use private registries for internal artifacts
- Review third-party modules/roles before adopting

## Compliance Reminders

- CIS benchmarks for Docker, Kubernetes, cloud providers
- OWASP top 10 for application code
- Audit logging enabled for all infrastructure changes
- Document security exceptions with justification

## When Reviewing Code

1. Scan for hardcoded secrets first
2. Check access control configurations
3. Verify encryption settings
4. Review network exposure
5. Validate dependency pinning
6. Flag any `TODO: security` or `FIXME: auth` comments
