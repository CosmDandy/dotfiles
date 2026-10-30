# Claude configuration compatibility for Pi

Apply the user instructions in the agent-directory CLAUDE.md. Those instructions
were authored for Claude Code. Adapt application-specific mechanisms as follows:

- Pi tools and their actual contracts take precedence over claims about Claude's
  shell, timeouts, automatic backgrounding, hooks, or available tools.
- Never claim a Claude PostToolUse lint hook ran here. Run applicable checks explicitly.
- AskUserQuestion means ask a plain chat question (or an available Pi dialog).
  ExitPlanMode, Monitor, run_in_background, /goal and subagents are not assumed
  available. Explain missing capabilities; do not pretend to invoke them.
- Skill frontmatter model: haiku/sonnet/opus does not select a Pi model.
  allowed-tools is not a Pi permission sandbox. Use only actually available tools.
- Invoke imported skills as /skill:<name>; arguments following the skill invocation
  are its $ARGUMENTS. Slash-command examples inside skills refer to that skill.
- Skills referring to macOS applications, MCP tools, Claude CLI/history, or external
  knowledge bases still require those dependencies. Check availability before use.
  Do not silently substitute Pi history for Claude history or vice versa.
- Missing independent subagent review is a verification limitation, not a review
  that happened. Report it honestly.

## Repository investigation

Before proposing an integration or editing unfamiliar code:

1. Identify repository instructions, branch, dirty files and submodules. Do not
   confuse the current workspace with a second repository named by the user.
2. Trace the actual entry points and import graph. For cross-platform setup,
   identify which modules load on each platform and profile before editing.
3. Inspect existing implementation, tests, update flow and deployment ownership.
   Cite the files that establish each consequential claim. A grep match is a
   lead, not evidence that a configuration is active.
4. Map reusable skills and integrations before suggesting replacements. Distinguish
   instructions from executable tools, installed binaries from authenticated
   services, and configured resources from resources available in this session.
5. State an explicit scope and preserve unrelated work. Use available independent
   reviewers when appropriate; otherwise report that limitation honestly.
6. Implement only after the task is authorized. Run checks covering the changed
   behavior, including the platform-specific configuration, and report gaps.

Do not invent automatic modes or pretend a model change fixes missing context.
Use a read-only investigation phase, then implementation, then verification as a
workflow, not as fictitious harness features. Do not export private skills,
project knowledge, time tracking, personal journals or credentials into a public
repository. Reference reviewed private resources through an explicit allowlist.

## Imported scoped rules

Claude's rules/ directory is not assumed to load automatically in Pi. Before
editing a file, read every applicable rule below; consult each file's paths
frontmatter for exact scope. They are available at ~/.pi/agent/claude-rules/.
Only the applicable rules need to be loaded; do not load unrelated rule bodies.

- ansible.md: Ansible playbooks, roles, inventories, variables and templates.
- ci.md: GitHub Actions and GitLab CI.
- docker.md: Dockerfiles, Compose and container build configuration.
- git.md: Git configuration, hooks and submodules.
- kubernetes.md: Kubernetes manifests, Helm, Kustomize and Talos configuration.
- nix.md: Nix files, flakes and home-manager.
- ops-files.md: Host inventories, SSH, network, boot and firewall configuration.
- python.md: Python source, dependencies and project configuration.
- security.md: Infrastructure/security-sensitive configuration; inspect its paths
  alongside the domain rule, as multiple rules can apply to the same file.
- shell.md: Shell scripts and startup files; establish dialect from the shebang.
- terraform.md: Terraform/OpenTofu source, variables and tests.

This is instruction-based rule routing, not a port of Claude's automatic scoped
rule injection or its permission/security enforcement.
