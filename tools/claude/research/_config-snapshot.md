# Снимок текущего конфига Claude Code (для ресёрч-агентов)

База: `/Users/cosmdandy/.dotfiles/tools/claude/`. Симлинкуется в `~/.claude/` через `custom/install.sh`.
Платформы: macOS (nix-darwin, M1) + Linux (DevPod/DevContainers). Today: 2026-06-18.

## settings.json
ENV: CLAUDE_CODE_DISABLE_ATTRIBUTION=1, CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=85,
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1, CLAUDE_CODE_AUTO_CONNECT_IDE=1,
CLAUDE_CODE_ENABLE_AWAY_SUMMARY=0, CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1,
CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=10, CLAUDE_CODE_FORK_SUBAGENT=1,
DISABLE_TELEMETRY=1, DISABLE_ERROR_REPORTING=1, EDITOR/VISUAL=nvim.
Permissions: ~200 allow, ~60 deny (secrets, destructive git/tf/k8s, curl|bash), 12 ask (docker).
Hooks: только Stop hook (printf bell).
Прочее: statusLine (кастомный скрипт), outputStyle=learning, language=Russian,
effortLevel=medium, autoDreamEnabled=true, skipDangerousModePermissionPrompt=true,
theme=auto, preferredNotifChannel=terminal_bell, voiceEnabled=true, fallbackModel=sonnet.

## Rules (custom/rules/) — path-scoped
terraform.md, kubernetes.md, ansible.md, nomad.md, docker.md, python.md (symlink),
security.md (always-on, без paths). Каждый содержит валидационные команды.

## Agents (custom/agents/) — 6 шт, все memory:user
tf-specialist (sonnet), k8s-specialist (sonnet), ansible-specialist (sonnet),
nomad-specialist (sonnet), infra-security (sonnet), container-lint (haiku).

## Skills (custom/skills/) — 12 шт
plan(opus), implement(sonnet), devops-review(opus), security-review(opus,fork),
code-review(sonnet,fork), c-daylog(sonnet), c-log(haiku), c-brag(sonnet),
cw-analyze-logs(opus), cw-analyze-pipeline(sonnet), init-project-memory(sonnet,fork),
commit(haiku).

## Knowledge (custom/knowledge/)
Проекты: dotfiles (9 memory-файлов), code-kvt/Odoo (11 memory), _template, homepage(пусто).
Portable memory через симлинки. brag-document-v2 (33KB, CAR format).

## MCP (custom/mcp/)
timing (кастомный Python MCP, stdio на macOS через launchd / http на Linux),
context7 (npx), atlassian/Jira (uvx mcp-atlassian).
Встроенные через claude.ai: Things3, Gmail, Google Calendar, Google Drive, Spokenly (voice).

## Прочее
statusline.sh (модель/контекст/cache/токены/burn rate, refresh 15s).
install.sh (симлинки + MCP), setup.sh (проектная knowledge база + portable memory).
Пустые: commands/, code/. Нет keybindings.json.

## Заявленные пробелы/вопросы
- commands/ и code/ пусты
- homepage project пуст
- python.md только symlink
- нет keybindings.json (defaults)
- мало hooks (только Stop)
- OpenSearch creds для cw-analyze-logs — неясно как ставятся
