---
paths:
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.tfvars.json"
  - "**/terraform/**"
---

# Terraform Conventions

## Mandatory Checks

- ALWAYS run `terraform validate` after any change
- ALWAYS run `terraform plan` before apply — show output to user
- ALWAYS run `terraform fmt -check` — auto-fix if needed
- Use `tflint` if available in the project

## State Management

- Remote state with locking (S3+DynamoDB, Consul, etc.)
- Never commit `.tfstate` files
- Use `terraform_remote_state` data source for cross-stack references
- State isolation: one state per environment

## Code Structure

- Use modules for reusable components
- Pin provider versions with `required_providers` block
- Pin module versions (git tags or registry versions)
- Variables: always set `type`, `description`, and `default` where appropriate
- Outputs: always set `description`

## Naming

- Resources: `snake_case`, descriptive (e.g., `aws_instance.web_server`)
- Variables: `snake_case`, prefix with context if ambiguous
- Modules: `kebab-case` directories

## Security

- No hardcoded secrets — use variables or vault
- Encrypt state at rest (S3 encryption, etc.)
- Use `sensitive = true` for secret outputs/variables
- Least privilege IAM policies — avoid `*` in actions/resources
- Enable logging/audit trails where applicable

## Common Mistakes

- Forgetting to run `terraform init` after adding providers/modules
- Using `count` when `for_each` is more appropriate (prevents index shift)
- Not using `lifecycle { prevent_destroy = true }` for critical resources
- Missing `depends_on` for implicit dependencies
- Hardcoding region/account values instead of using variables/data sources

## Validation Commands

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
tflint --recursive          # if available
```
