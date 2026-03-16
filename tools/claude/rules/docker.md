---
paths:
  - "**/Dockerfile*"
  - "**/docker-compose*"
  - "**/compose*"
  - "**/.dockerignore"
  - "**/docker/**"
---

# Docker Conventions

## Mandatory Checks

- Lint Dockerfiles: `hadolint Dockerfile` if available
- Validate compose: `docker compose config`
- Check image size after build — flag bloat

## Dockerfile Best Practices

- Multi-stage builds — separate build and runtime stages
- Pin base image versions explicitly (never `:latest` in production)
- Use digest pinning for critical images (`image@sha256:...`)
- Order layers: least-changing first (OS deps -> app deps -> code)
- Combine `RUN` commands to reduce layers
- Clean up in the same `RUN` layer (`apt-get clean && rm -rf /var/lib/apt/lists/*`)

## Security (CIS Benchmark)

- `USER` directive — NEVER run as root
- No secrets in build args or environment — use build secrets (`--mount=type=secret`)
- Minimal base images: `distroless`, `alpine`, or `-slim` variants
- `COPY` specific files, not entire directories (use `.dockerignore`)
- No `sudo`, `ssh`, or unnecessary tools in production images
- Set `HEALTHCHECK` instruction
- Read-only filesystem where possible

## Compose Best Practices

- Pin service image versions
- Set resource limits (`deploy.resources.limits`)
- Use named volumes for persistent data
- Network isolation: custom networks, not default bridge
- Environment: use `env_file`, not inline secrets
- `restart: unless-stopped` for production services

## Common Mistakes

- `COPY . .` without proper `.dockerignore` (copies secrets, .git, etc.)
- Installing dev dependencies in production image
- Running as root (missing `USER` directive)
- Not leveraging build cache (wrong layer order)
- Using `ADD` when `COPY` suffices (ADD has extra features that surprise)
- Missing `.dockerignore` file
- `apt-get install` without `-y` and `--no-install-recommends`

## Validation Commands

```bash
hadolint Dockerfile                  # if available
docker compose config               # validate compose
docker build --target runtime .      # test build
docker scout cves <image>            # vulnerability scan (if available)
```
