---
paths:
  - "**/playbooks/**"
  - "**/roles/**"
  - "**/ansible/**"
  - "**/inventory/**"
  - "**/group_vars/**"
  - "**/host_vars/**"
  - "**/*.yml"
  - "**/*.yaml"
---

# Ansible Conventions

## Mandatory Checks

- ALWAYS run `ansible-lint` before commit
- ALWAYS run `ansible-playbook --check --diff` before real execution
- Show diff output to user before applying changes
- Use `--syntax-check` for quick validation

## Idempotency

- Every task MUST be idempotent — running twice produces same result
- Use modules over `command`/`shell` — modules are idempotent by default
- If `command`/`shell` is unavoidable, use `creates`/`removes` or `changed_when`
- Never use `shell` when a module exists for the task

## Code Structure

- One role = one responsibility
- Use `ansible.builtin.` FQCN for all modules
- Variables: `defaults/main.yml` for overridable, `vars/main.yml` for internal
- Handlers: always use `notify` + handlers, not inline restarts
- Tags: use meaningful tags for selective execution

## Naming

- Roles: `snake_case`, descriptive purpose
- Variables: prefix with role name (e.g., `nginx_port`, `postgres_max_connections`)
- Tasks: start with verb, describe what happens (e.g., "Install nginx packages")
- Files: `main.yml` for entry points, descriptive names for includes

## Security

- Secrets via `ansible-vault` only — never plaintext
- Use `no_log: true` for tasks handling sensitive data
- Limit `become: true` to tasks that need it, not entire plays
- Pin collection/role versions in `requirements.yml`

## Common Mistakes

- Missing `become: true` for privileged operations
- Using `shell` with pipes when `command` + register would work
- Not quoting YAML values that start with `{`, `[`, `*`, `&`, `!`
- Forgetting `changed_when: false` for check/info-gathering commands
- Using `with_items` (legacy) instead of `loop`

## Validation Commands

```bash
ansible-lint .
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --check --diff
yamllint .                    # if available
```
