---
paths:
  - "**/k8s/**"
  - "**/manifests/**"
  - "**/charts/**"
  - "**/helm/**"
  - "**/*deployment*"
  - "**/*service*"
  - "**/*ingress*"
  - "**/kustomization*"
---

# Kubernetes Conventions

## Mandatory Checks

- Show diff before applying manifest changes
- Run `kubectl diff` or `helm diff` before apply
- Validate manifests: `kubectl apply --dry-run=client -f`
- Use `kubeval` or `kubeconform` for schema validation if available

## Resource Requirements

- Resource `requests` and `limits` are MANDATORY for all containers
- Set both CPU and memory — never skip one
- Requests ~= actual usage, limits = reasonable ceiling
- Use LimitRange/ResourceQuota at namespace level

## Health Checks

- `livenessProbe` — required: restarts unhealthy pods
- `readinessProbe` — required: controls traffic routing
- `startupProbe` — for slow-starting apps
- Set appropriate `initialDelaySeconds`, `periodSeconds`, `failureThreshold`

## Security

- RBAC with minimal privileges — never use `cluster-admin` for apps
- `securityContext`: `runAsNonRoot: true`, `readOnlyRootFilesystem: true`
- No `privileged: true` unless absolutely necessary (document why)
- NetworkPolicies: default-deny ingress, allow only needed
- Secrets: use external secrets operator or sealed-secrets, not plaintext

## Code Structure

- One resource per file, or logically grouped (deploy + service + ingress)
- Use labels consistently: `app.kubernetes.io/name`, `app.kubernetes.io/version`
- Namespaces: isolate by team/environment
- Use Kustomize overlays or Helm values for environment differences

## Common Mistakes

- Missing resource requests/limits (causes noisy neighbor, OOM kills)
- No PodDisruptionBudget for critical services
- Using `latest` tag (breaks reproducibility)
- Forgetting anti-affinity rules for HA deployments
- Not setting `terminationGracePeriodSeconds` appropriately
- Missing `topologySpreadConstraints` for multi-zone

## Validation Commands

```bash
kubectl apply --dry-run=client -f manifest.yaml
kubectl diff -f manifest.yaml
kubeconform -strict manifest.yaml    # if available
helm template . | kubeconform        # for Helm charts
```
