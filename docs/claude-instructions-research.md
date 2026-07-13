# Модернизация Claude Code стека: research-отчёт

**Дата:** 2026-07-13
**Область:** глобальный CLAUDE.md, path-scoped rules, 13 skills, 6 DevOps-агентов, settings/permissions, hooks
**Модели:** Fable 5 (`claude-fable-5[1m]`, основная) / Opus 4.8 / Sonnet 5 / Haiku 4.5

Этот отчёт — синтез пяти research-направлений (agentic prompting, CLAUDE.md best practices, обзор фич Claude Code, community-опыт автономности и DevOps, ментор-режим) и gap-анализа текущего стека. Цель — подготовить заход №2: переписывание инструкционного стека под четыре цели пользователя: (1) полная автономность делегированных задач, (2) проактивный выбор инструментов, (3) DevOps-практики как рефлексы рассуждения без жёсткой роли, (4) ментор-режим 90/10 в интерактиве. Здесь только анализ и рекомендации — файлы стека не изменялись.

---

## 1. TL;DR

1. **Главный конфликт стека — режимы исполнения.** Секция Workflow («STOP — wait for next instruction», строки 33–36 CLAUDE.md) прямо противоречит цели полной автономности делегированных задач; при конфликте инструкций модель выбирает произвольно. Решение: двухрежимная шапка INTERACTIVE vs DELEGATED в начале CLAUDE.md.
2. **Ментор-режим 90/10 нигде не закодирован** — ключевая цель без единой строчки в стеке. Реализовать как секцию CLAUDE.md с mode-guard «INTERACTIVE only» и keyword-override («быстро» / «научи»), а НЕ через output style: встроенные Learning/Explanatory — session-wide и требуют /clear.
3. **Проза противоречит permissions:** «NOT push by default» vs `Bash(git push:*)` в allow (settings.json:219); «NOT create PRs/MRs» vs blanket `Bash(gh:*)`/`Bash(glab:*)` (строки 220–221). Hard limits — в permissions/hooks, суждения — в прозе; push и pr/mr create перенести в ask.
4. **Мёртвые и ложные срабатывания в rules:** python.md — битый цикличный симлинк на самого себя (удалить); ansible.md матчится на ЛЮБОЙ yaml через `**/*.yml`/`**/*.yaml` (сузить до ansible-путей); security.md грузится в каждую сессию без `paths:` (скоупить на инфра-файлы).
5. **Модельные тиры почти оптимальны, 3 точечные правки:** implement sonnet→opus (ядро автономного исполнения), infra-security sonnet→opus (цена false-negative), fallbackModel `["sonnet"]`→`["opus","sonnet"]` (не падать с Fable 5 сразу на Sonnet).
6. **Субагенты без `tools:` наследуют всё, включая Edit/Write/полный Bash** — все 6 ревью-агентов должны получить read-only список инструментов; та же проблема у skill read-only (неограниченный `Bash` в allowed-tools).
7. **Стиль инструкций под Fable 5/Opus 4.8 требует ревизии:** CAPS-императивы и анти-lazy пошаговые чек-листы, написанные под слабые модели, на новых вызывают overtriggering и режут качество — заменить на outcome-формулировки с объяснением причин.

---

## 2. Принципы инструкций для Fable 5 / Opus 4.8

Официальные гайды Anthropic ([claude-prompting-best-practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices), [prompting-claude-fable-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5), [prompting-claude-sonnet-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5)) фиксируют смену парадигмы, напрямую затрагивающую текущий стек.

### Что изменилось

- **Explicit but not micromanaged.** Модели 4.x/5 «берут инструкции буквально и делают ровно то, что просят». Golden rule: покажи промпт коллеге без контекста — если запутается он, запутается и Claude. Путь — ясность цели и контекст, а не перечисление всех шагов.
- **Outcome вместо чек-листов.** «Prefer general instructions over prescriptive steps» — рассуждение модели часто превосходит рукописный план. Для Fable 5 отдельно: «you can steer most behaviors with a brief instruction rather than enumerating each behavior by name». Практика: короткая outcome-формулировка + 2–3 канонических примера вместо исчерпывающего списка edge cases ([effective-context-engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — «right altitude», экономия attention budget).
- **Причина вместо голого запрета.** «NEVER use ellipses» работает хуже, чем «ответ читается TTS-движком, поэтому не используй многоточия» — с причиной модель корректно генерализует правило на смежные случаи. Для Fable 5: «Give the reason, not only the request».
- **Автономность в long-horizon задачах** — готовые паттерны из официального раздела Long-horizon reasoning: явно сообщать, что контекст авто-компактифицируется и нельзя останавливаться из-за token budget («Never artificially stop any task early»); для автономных пайплайнов — «You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task... For reversible actions that follow from the original request, proceed without asking»; не заканчивать ход планом/обещанием — доделывать tool-calls; аудировать каждое утверждение статуса по фактическому tool-результату.

### Анти-паттерны на новых моделях

| Анти-паттерн | Почему вреден | Где в стеке |
|---|---|---|
| CAPS-императивы («CRITICAL: You MUST use...») | Overtriggering на Opus 4.5+/Fable 5, а не лучшее срабатывание; официальная рекомендация — «dial back aggressive language» | CLAUDE.md: «Never suggest `! command`», «DON'T add docstrings», «Do NOT use agents» — частично наследие под слабые модели |
| Анти-lazy пошаговые чек-листы | Новые модели «agentic by default» — избыточная дотошность инструкций режет качество | Секция Workflow (шаги 1–4), потенциально часть 13 skills |
| «If in doubt, use [tool]» / «Default to using [tool]» | Overtriggering; заменять на «Use [tool] when it would enhance understanding» | Проверить skills/agents при переписывании |
| Prefill (частичный assistant-ответ) | Не поддерживается с Claude 4.6 / Fable 5 — 400 error | Проверить workflow-скрипты |
| Ручной thinking `budget_tokens` | Удалён на Opus 4.7+/Sonnet 5/Fable 5 — 400 error; заменён adaptive thinking + effort | Проверить API-вызовы в скриптах |
| «Покажи своё reasoning в ответе» | На Fable 5 может триггерить refusal (reasoning_extraction) | Проверить промпты агентов |
| Overengineering (лишние файлы, defensive coding, docstrings к чужому коду) | Задокументированная склонность мощных моделей; есть готовый блок-противоядие Anthropic | Текущее «Do NOT make unrequested changes» — правильное, официально подтверждено |

### Специфика моделей стека

- **Fable 5** (основная): рассчитан на многочасовые/многодневные автономные прогоны, сильнее держит инструкции; на высоком effort может overplan/переобъяснять — есть готовый anti-verbosity блок «Lead with the outcome». Устаревшие прескриптивные skills деградируют его вывод — их стоит ревизовать.
- **Sonnet 5** (research/ревью-агенты): более литеральная — не обобщает инструкцию с одного случая на все, scope указывать явно («apply to every section, not just the first»); effort по умолчанию high, для сложных agentic задач — xhigh.
- **Opus 4.8**: default main model, 1M context; надёжнее Sonnet на длинном автономном исполнении ([features-survey / changelog](https://code.claude.com/docs/en/changelog.md)).

Источники: [claude-prompting-best-practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices), [prompting-claude-fable-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5), [prompting-claude-sonnet-5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5), [effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [building-effective-agents](https://www.anthropic.com/research/building-effective-agents).

---

## 3. Ментор-режим 90/10: дизайн

Ключевая цель (goal 4) сейчас не закодирована никак. Дизайн из gap-анализа:

### Механизм

**ОДНА секция в CLAUDE.md** `## Mentor mode (INTERACTIVE only)` с явным mode-guard. НЕ output style и НЕ отдельный skill.

**Дефолт (интерактив, ~90%):** на нетривиальной / необратимой / архитектурной / новой для пользователя работе Claude:
1. проговаривает своё рассуждение ДО действия;
2. задаёт один наводящий вопрос (Socratic questioning — подтверждённый паттерн Anthropic из [Claude for Education](https://www.anthropic.com/news/introducing-claude-for-education): «How would you approach this problem?» вместо готового решения);
3. показывает 2–3 варианта с трейд-оффами и оставляет решение за пользователем;
4. добавляет краткое обоснование каждого выбора.

**Fast path (~10%):** срочное / рутинное / чисто механическое / явно делегированное — делает сразу, показывает результат.

**Keyword-override внутри одной сессии, без /clear:**
- «быстро» / «сделай молча» / «just do it» → форс fast path;
- «научи» / «разбери» / «объясни» → форс ментор даже на рутине.

### Почему не output style

Встроенные Learning/Explanatory ([output-styles docs](https://code.claude.com/docs/en/output-styles)) — session-wide: стиль читается один раз при старте как часть system prompt, переключение вступает в силу только после /clear или новой сессии. Per-task свитч 90/10 и keyword-override они дать не могут — официального per-task механизма нет (caveat research mentor-mode), его строят промптом. Кроме того, механика Learning (`★ Insight` блоки + `TODO(human)` в файле) заточена под write-code сценарии и слабо покрывает DevOps-работу (разбор логов, ssh-диагностику, terraform).

Learning остаётся как опциональный «тяжёлый» режим на всю сессию для глубоких обучающих сессий: `/config → Output style → Learning`.

### Почему не ломает фоновые/делегированные задачи — три независимых барьера

1. **Guard-clause в самой секции:** «INTERACTIVE only — void in delegated/background/headless/subagent runs». Как только человек не наблюдает, секция самоотключается и действует autonomy-блок.
2. **Субагенты не наследуют CLAUDE.md-контекст основной сессии:** Task/6 DevOps-агентов и skills с `context: fork` исполняются со своим system prompt ([sub-agents docs](https://code.claude.com/docs/en/sub-agents.md): «Runs a subagent with its own system prompt, model, and tools») — mentor-текст туда физически не попадает.
3. **Cloud Routines / headless `-p` / scheduled прогоны** имеют собственный промпт ([headless docs](https://code.claude.com/docs/en/headless)); в их определениях mentor-текст не прописывается, а guard-clause страхует, даже если CLAUDE.md подхватится (не `--bare` режим).

Каveat: наследование output style субагентами официально не подтверждено дословно — вывод по косвенным признакам; при заходе №2 стоит разово проверить на одном из 6 агентов.

Обоснование педагогики: Socratic/guided discovery — задокументированная практика Anthropic; desirable difficulty (Bjork & Bjork; [Kestin et al. 2025](https://etcjournal.com/2025/11/10/review-of-kestin-et-al-s-june-2025-harvard-study-on-ai-tutoring/), [Nature Sci. Reports 2025](https://www.nature.com/articles/s41598-025-97652-6)) — обосновывающая теория, но не фича продукта.

---

## 4. Рекомендации по слоям

### 4.1 CLAUDE.md (глобальный, 56 строк)

**Критика текущего по пунктам:**

| Пункт | Вердикт | Суть |
|---|---|---|
| Mode-gating размазан (строки 5 и 31) | change, high | «In agent mode: use best judgment» и «Delegated agents should complete their full task autonomously» конфликтуют с «STOP — wait for next instruction» (строка 36) и «state the approach and wait for confirmation» (строка 10). При конфликте модель выбирает произвольно ([memory docs](https://code.claude.com/docs/en/memory)) |
| Workflow «2-3 changes → STOP» | change, high | Интерактивный микроменеджмент, ломающий делегированные прогоны; анти-lazy чек-лист под слабые модели. Ограничить: «applies to INTERACTIVE mode only» |
| Autonomy-блок | add, high | Отсутствует полностью; взять формулировки Anthropic почти дословно (см. скелет) |
| Mentor mode 90/10 | add, high | См. раздел 3 |
| Operational reflexes | add, high | dry-run / blast radius / evidence / rollback / verify как рефлексы на любые задачи, без роли «ты девопс». Сейчас blast radius живёт только в skill plan |
| Проактивный выбор инструментов + Artifacts | change, medium | Commands-секция покрывает ssh/diагностику; добавить ssh-алиасы из ~/.ssh/config, kubectl/helm/jq/rg/fd, Artifacts для отчётов |
| CAPS-тон | change, low | «Never suggest `! command`» → нейтральное «Prefer running commands yourself»; эмфазу (IMPORTANT/YOU MUST) оставить только на критичном (не пушить без спроса, не коммитить секреты) — там она официально оправдана |
| Communication / General Rules / Agents | keep | Структура заголовки+буллеты соответствует best practices; 56 строк — сильно под лимитом 200; «Do NOT make unrequested changes» подтверждён официальным anti-overengineering блоком |

**Скелет нового CLAUDE.md (черновик для захода №2):**

```markdown
# Global Claude Code Instructions

## Execution mode (read first)

- INTERACTIVE (main session, human present): short iterations, mentor 90/10
  (see below), propose-and-confirm on non-trivial work.
- DELEGATED (subagent / background / headless -p / scheduled): you are operating
  autonomously — the user is not watching in real time and cannot answer
  questions mid-task. For any reversible action that follows from the original
  request, proceed without asking. Never artificially stop a task early for
  token/budget reasons; auto-compaction is expected. Do not end a turn on a plan
  or a promise — finish it with tool calls. Audit every status claim against an
  actual tool result; report outcomes faithfully.
- Hard limits (permissions deny/ask + PreToolUse guard) apply in BOTH modes.

## Mentor mode (INTERACTIVE only — void in delegated/background/headless/subagent runs)

Default to teaching (~90%): on non-trivial, irreversible, architectural, or
new-to-me work — walk me through your reasoning BEFORE acting, ask one guiding
question, surface 2-3 options with tradeoffs, and let me make the call. Add a
short rationale for each decision. The goal is that the work passes through me,
not past me.
Fast path (~10%): urgent, routine, purely mechanical, or explicitly delegated —
just do it, show the result.
Overrides (per-task, no /clear needed):
- "быстро" / "сделай молча" / "just do it" → force fast path
- "научи" / "разбери" / "объясни" → force mentor, even on routine work

## Operational reflexes (all modes, any task)

- Evidence before action: read current state before you change it.
- Dry-run first for anything mutating: terraform plan, kubectl diff /
  --dry-run=client, helm diff, ansible --check. Show it.
- Assess blast radius and environment (dev/stage/prod) before acting; treat
  prod as confirm-required even if a command is technically allowed.
- Know the rollback path before you apply.
- Verify after: re-read state / re-run the check to confirm the change landed.

## Communication

- Communicate in Russian when the user writes in Russian. Code — in English.
- Do actions silently, show only results. After a batch: brief summary.
- Don't add docstrings, comments, or documentation unless asked.

## Tools

- Run commands yourself when permitted — diagnostics (ssh, logs, status,
  network) included; don't hand them back to the user.
- Reach for the right tool proactively: ssh to my servers via ~/.ssh/config
  aliases; gh for GitHub, glab for GitLab (never raw curl/API); jq/yq for
  JSON/YAML; rg/fd for search; kubectl/helm/terraform/nomad for infra
  inspection.
- For any multi-section report, analysis, or review meant to be read or
  shared — build an Artifact instead of dumping long markdown into the
  terminal.
- If a command fails — read the error, adjust, retry.

## Workflow (INTERACTIVE)

1. Make 2-3 related changes (one logical block)
2. Run tests/linters to verify
3. Show result; STOP — wait for next instruction
- In DELEGATED mode: complete the whole task end-to-end, verify, report once.
- If tests/linters fail — auto-fix and re-run, show final status.
- Tasks affecting 5+ files — start with plan mode.

## Git

- You CAN: status, diff, log, blame, add, commit, amend.
- Push and PR/MR creation are confirm-gated (permissions ask) — only on
  explicit request or as part of a requested full cycle.
- Commit only when explicitly asked. Conventional commits. Show status after.

## Agents

- Use parallel agents for multi-file review and broad research; background
  agents for work independent of the current task.
- Don't use agents for single-file edits or simple sequential tasks.
```

Ориентир: ~90 строк — с запасом до лимита 200 ([best-practices](https://code.claude.com/docs/en/best-practices)); тест каждой строки — «удаление приведёт к ошибке Claude?».

### 4.2 Rules (`tools/claude/custom/rules/`)

| Файл | Вердикт | Действие |
|---|---|---|
| **python.md** | remove, high | Битый цикличный симлинк на самого себя (`python.md -> .../rules/python.md`, подтверждено `test -e` → BROKEN). `rm tools/claude/custom/rules/python.md`. Опционально — создать настоящий rule с `paths: ["**/*.py", "**/pyproject.toml"]` (в permissions разрешены python/pytest/ruff/mypy), но это отдельное решение |
| **ansible.md** | change, high | В `paths:` присутствуют `**/*.yml` и `**/*.yaml` — rule срабатывает на любой yaml (k8s-манифесты, docker-compose, CI), коллизия с kubernetes.md/docker.md. Убрать оба глоба, оставить структурные: `**/playbooks/**`, `**/roles/**`, `**/ansible/**`, `**/inventory/**`, `**/group_vars/**`, `**/host_vars/**`, добавить `**/site.yml`, `**/playbook*.yml`, `**/*.ansible.yml`. Эталон детекта — собственный posttooluse-lint.sh, который определяет ansible по путям tasks/playbooks/roles |
| **security.md** | change, high | 52 строки без `paths:` → грузится в КАЖДОЙ сессии, включая research/консьюмерские (виден и в этой). Добавить frontmatter `paths:` на инфра-файлы (`**/*.tf`, `**/*.tfvars`, `**/*.yml`, `**/*.yaml`, `**/Dockerfile*`, `**/*.nomad*`, `**/k8s/**`, `**/helm/**`). Чеклист «When Reviewing Code» перенести в тело skill security-review. Enforcement-часть («NEVER commit secrets») продублировать хуком — см. 4.5 |
| terraform / docker / kubernetes / nomad | keep | Корректный официальный паттерн path-scoped rules; периодически резать самоочевидное (часть «Common Mistakes» в terraform.md модель знает и так) |

Источник паттерна: [memory docs](https://code.claude.com/docs/en/memory) — «глубокое, тематически- или path-специфичное, или релевантное лишь иногда — в rules, не в CLAUDE.md». @-импорты контекст НЕ экономят (грузятся полностью) — только организация.

### 4.3 Skills — модельные тиры (13)

| Skill | Текущая | Рекомендуемая | Почему |
|---|---|---|---|
| c-brag | sonnet | sonnet (Sonnet 5) | Лёгкая-средняя задача; near-Opus качество Sonnet 5 достаточно |
| c-daylog | sonnet | sonnet (Sonnet 5) | Оркестрация Timing→Jira, умеренная сложность |
| c-log | haiku | haiku (Haiku 4.5) | Тривиальное обогащение записи — самая дешёвая модель уместна |
| code-review | sonnet | sonnet (Sonnet 5) | Ревью с `context: fork`; опционально opus для критичного кода |
| commit | haiku | haiku (Haiku 4.5) | Механическая генерация conventional-commit |
| cw-analyze-logs | opus | opus (Opus 4.8) | On-call диагностика, высокая цена ошибки; для ночного routine — fable-5 |
| cw-analyze-pipeline | sonnet | sonnet (Sonnet 5) | Диагностика пайплайнов через glab; поднимать до opus только при стабильно трудных кейсах |
| devops-review | opus | opus (Opus 4.8) | Оркестратор специалистов — нужно opus-рассуждение |
| **implement** | **sonnet** | **opus (Opus 4.8)** | Ядро автономного исполнения плана (goal 1) — надёжность важнее экономии; Opus устойчивее на длинных прогонах. Для самых длинных — claude-fable-5 |
| init-project-memory | sonnet | sonnet (Sonnet 5) | Скан проекта, умеренная задача |
| plan | opus | opus (Opus 4.8) | Blast radius + rollback — высокое рассуждение; для сложнейших планов рассмотреть fable-5 |
| read-only | (наследует) | (наследует Fable 5) | Правильно не пинить модель; ценность — в ограничении tools |
| security-review | opus | opus (Opus 4.8) | Высокая цена false-negative; опционально fable-5 для глубоких аудитов |

**Прочие правки skills:**

- **read-only** (change, medium): `allowed-tools` содержит неограниченный `Bash` (подтверждено в SKILL.md) — проза «never modify» advisory, а `git commit`/`mv`/`rm` guard не ловит. Сузить до read-глаголов: `Bash(ls:*), Bash(cat:*), Bash(rg:*), Bash(fd:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(kubectl get:*), Bash(kubectl describe:*), Bash(kubectl logs:*), Bash(terraform show:*), Bash(terraform state list:*), Bash(ssh:*), Bash(jq:*), Bash(yq:*)` (ssh оставить — нужен для инспекции серверов).
- **read-only + commit** (add, low): `disable-model-invocation: true` — только явный вызов `/read-only`, `/commit`; авто-инвокация по описанию нежелательна.

### 4.4 Agents (6)

| Agent | Текущая | Рекомендуемая | Почему |
|---|---|---|---|
| ansible-specialist | sonnet | sonnet (Sonnet 5) | Доменное ревью — Sonnet 5 достаточно |
| container-lint | haiku | haiku (Haiku 4.5) | Механический lint против CIS |
| **infra-security** | **sonnet** | **opus (Opus 4.8)** | Кросс-стековый security-анализ; пропуск секрета/RBAC/шифрования дорог — платим за меньший false-negative rate |
| k8s-specialist | sonnet | sonnet (Sonnet 5) | Ревью манифестов/Helm/Kustomize |
| nomad-specialist | sonnet | sonnet (Sonnet 5) | Ревью jobspec/update-стратегий |
| tf-specialist | sonnet | sonnet (Sonnet 5) | Ревью Terraform/state/HCL |

**Frontmatter-правки (add, high):** все 6 агентов без поля `tools:` → наследуют ВСЕ инструменты родителя, включая Edit/Write/полный Bash. Все шесть — ревью-агенты, писать им нечего; неограниченные tools = лишний blast radius ([sub-agents](https://code.claude.com/docs/en/sub-agents.md); community-принцип «read access is generous, write access requires human approval», [ellamind](https://www.ellamind.com/blog/infra-ops-with-claude-code)). Выдать каждому read-only набор:

```yaml
# tf-specialist
tools: Read, Grep, Glob, WebFetch, Bash(terraform validate:*), Bash(terraform plan:*), Bash(terraform fmt:*), Bash(terraform show:*), Bash(tflint:*)
# k8s-specialist
tools: Read, Grep, Glob, WebFetch, Bash(kubectl get:*), Bash(kubectl describe:*), Bash(kubectl diff:*), Bash(helm template:*), Bash(helm lint:*), Bash(kubeconform:*)
# ansible-specialist
tools: Read, Grep, Glob, WebFetch, Bash(ansible-lint:*), Bash(ansible-inventory:*), Bash(ansible-doc:*)
# nomad-specialist
tools: Read, Grep, Glob, WebFetch, Bash(nomad job validate:*), Bash(nomad job plan:*), Bash(nomad status:*)
# container-lint
tools: Read, Grep, Glob, Bash(hadolint:*), Bash(docker build:*)
# infra-security (никаких Edit/Write/apply)
tools: Read, Grep, Glob, WebFetch, Bash(rg:*), Bash(gitleaks:*), Bash(tfsec:*), Bash(trivy:*), Bash(checkov:*)
```

`memory: user` на всех агентах — keep: persistent auto-memory накапливает паттерны из правок пользователя, согласуется с ментор-целью.

### 4.5 Settings / permissions / hooks: проза ↔ hard limits

Принцип (research community-autonomy, [permissions docs](https://code.claude.com/docs/en/permissions), [hooks](https://code.claude.com/docs/en/hooks)): **hard limits in code, judgment in prose**. CLAUDE.md — advisory (модель следует вероятностно); permissions deny/ask и hooks — детерминированны. Порядок проверки: deny → ask → allow, deny с любого уровня бьёт allow.

**Из прозы → в permissions/hooks:**

1. **`Bash(git push:*)` из allow (settings.json:219) → ask.** Сейчас прямое противоречие: проза «By default: NOT push» (CLAUDE.md:45) vs молчаливый allow. Push — «visible to others», официально рекомендован confirm. Делегированным прогонам, которым push легитимно нужен, — узкий allow в permissions самого агента/прогона, не глобально. Это и есть разрешение конфликта автономность-vs-безопасность.
2. **Удалить blanket `Bash(gh:*)` и `Bash(glab:*)` (строки 220–221).** Они перекрывают гранулярные gh pr/glab mr правила и делают `gh pr create` авто-запускаемым вопреки прозе «NOT create PRs/MRs». Оставить гранулярные, добавить в ask: `Bash(gh pr create:*)`, `Bash(glab mr create:*)`. Deny на merge уже есть.
3. **Secret-scan хук на git add/commit (add, medium).** «NEVER commit secrets» из security.md — чистая проза. Добавить в pretooluse-guard.sh (или отдельный PreToolUse с matcher Bash): на `git commit`/`git add` сканировать staged-дифф gitleaks-ом (`command -v gitleaks`, иначе grep по `-----BEGIN|api_key=|_TOKEN=|password=`) → deny с причиной. Официальная рекомендация: «инструкция, которая должна выполняться в конкретный момент — hook, а не CLAUDE.md» ([memory docs](https://code.claude.com/docs/en/memory)).
4. **Prod-gate в permissions (add, medium).** Классификация окружений (goal 3) в permissions не отражена. Добавить в ask (или deny): `Bash(kubectl * --context=*prod*)`, `Bash(kubectl * --context=*production*)`, `Bash(helm * --kube-context=*prod*)`, `Bash(terraform workspace select prod*)`. Дополнительно — direnv + путь kubeconfig для авто-детекта окружения (паттерн [ellamind](https://www.ellamind.com/blog/infra-ops-with-claude-code)).
5. **`Bash(rm:*)` (строка 87) → ask (строгий вариант, рекомендован).** Guard ловит только рекурсивный delete /~; плоский `rm important_file` сейчас авто-выполняется — с учётом автономных прогонов лучше confirm.
6. **`fallbackModel: ["sonnet"]` → `["opus", "sonnet"]`** — при недоступности Fable 5 деградация сначала до Opus 4.8, не сразу до Sonnet.

**Что остаётся прозой (правильно):** operational reflexes (dry-run/evidence/rollback/verify), mentor-логика, режимы исполнения, стиль коммуникации, конвенции — это «как рассуждать», enforcement здесь не нужен.

**Keep без изменений:**

- **pretooluse-guard.sh** — эталонный детерминированный backstop: работает даже под `--dangerously-skip-permissions` (что делает `skipDangerousModePermissionPrompt: true` безопасным), ловит destructive infra / secret-exfil / reverse-shell. Дублирование с settings.deny — осознанный belt-and-suspenders. Отдельный довод не ослаблять: открытый риск [issue #39027](https://github.com/anthropics/claude-code/issues/39027) — по завершении фоновой задачи при простаивающем REPL уведомление может материализоваться как синтетическое user-сообщение с bypassPermissions → автономный tool-call без промпта (community-репорт, не подтверждённое поведение — трактовать как риск).
- **posttooluse-lint.sh** — async, non-blocking, корректный детект ansible по путям (эталон для правки ansible.md).
- **env-блок** (`CLAUDE_CODE_FORK_SUBAGENT=1`, `MAX_TOOL_USE_CONCURRENCY=10`, `AUTOCOMPACT_PCT_OVERRIDE=85`, `RESUME_INTERRUPTED_TURN=1`), `model: claude-fable-5[1m]`, `effortLevel: xhigh`, `outputStyle: default` — всё работает на автономность.

**Опционально (add, low):** InstructionsLoaded-хук с логом в `~/.claude/logs/instructions.log` — разовая диагностика после правок paths в ansible.md/security.md, потом убрать.

---

## 5. Новые фичи Claude Code, которые стоит взять

Факты сверены с официальной документацией (features-survey). Для каждой: что это / зачем / как включить.

1. **Cloud Routines (`/schedule`)** — облачные recurring/triggered задачи на инфре Anthropic (schedule/API/GitHub triggers), выполняются автономно без permission-промптов. Зачем: ночной прогон cw-analyze-logs по develop/stage/master, утренний PR/MR review, backlog grooming — goal 1 в чистом виде. Как: `/schedule create` с промптом; в system prompt routine НЕ прописывать mentor-текст (just-do-it по умолчанию). [routines.md](https://code.claude.com/docs/en/routines.md)
2. **`/loop` c self-pacing** — повтор промпта в сессии: фиксированный интервал (`/loop 5m <проверка>`) или динамический (модель сама выбирает 1m–1h по прогрессу); `loop.md` кастомизирует дефолтный промпт. Зачем: поллинг деплоев/пайплайнов без ручного опроса. [scheduled-tasks.md](https://code.claude.com/docs/en/scheduled-tasks.md)
3. **Monitor tool** — переводит ожидание фоновых Bash-задач с polling на interrupt-driven: агент получает уведомление о событии вместо периодического опроса. Зачем: ждать долгие terraform apply/CI без сжигания токенов на опрос. Конфига не требует — рабочая привычка. [community-обзор](https://www.mindstudio.ai/blog/claude-code-monitor-tool-stop-polling-background-processes)
4. **Remote Control (`claude remote-control`, `/rc`)** — локальная сессия, доступная из claude.ai/code и мобильного приложения; server mode, 32+ параллельных сессий, worktree-изоляция. Зачем: контролировать долгие делегированные прогоны с телефона. [remote-control.md](https://code.claude.com/docs/en/remote-control.md)
5. **Agent View / background sessions (`claude agents`, `/bg`)** — фоновые сессии с PR-статусами, dispatch Bash-команд (`! pytest -x`), автоматические PR. Зачем: инкрементальные исследования и независимые задачи параллельно основной работе (уже поощряется секцией Agents в CLAUDE.md). [agent-view.md](https://code.claude.com/docs/en/agent-view.md)
6. **Dynamic Workflows + nested subagents (до 5 уровней)** — Claude пишет workflow-скрипты, оркеструющие десятки агентов. Зачем: multi-level investigation (research → analyze → validate) для сложных аудитов вроде этого. [workflows.md](https://code.claude.com/docs/en/workflows.md)
7. **Enhanced hooks (v2.1.195+)** — `async: true` (non-blocking логирование/нотификации), `if`-фильтры по tool/args (напр. только `terraform apply*`, не plan), HTTP hooks, per-subagent hooks. Важный нюанс: `if`-фильтры best-effort — жёсткий allow/deny держать в permissions, не в условной логике хука. [hooks-guide.md](https://code.claude.com/docs/en/hooks-guide.md)
8. **Output style Learning/Explanatory** — обучающие блоки `★ Insight` + `TODO(human)` (Learning ждёт, пока пользователь напишет 5–10 строк осмысленного кода, затем даёт фидбек). Зачем: опциональный тяжёлый режим для отдельных обучающих сессий; НЕ основа ментор-механизма (session-wide, требует /clear, заточен под write-code). Как: `/config → Output style`. [output-styles](https://code.claude.com/docs/en/output-styles)
9. **`fallbackModel` как массив** — многоуровневая деградация при rate-limit/недоступности. Как: `"fallbackModel": ["opus", "sonnet"]` в settings.json (см. 4.5 п.6). [settings.md](https://code.claude.com/docs/en/settings.md)
10. **Skills frontmatter: `context: fork`, `allowed-tools`, `disable-model-invocation`** — уже частично используется в стеке; добрать `disable-model-invocation: true` для read-only/commit и суженные `allowed-tools` для read-only (см. 4.3). [skills.md](https://code.claude.com/docs/en/skills.md)

---

## 6. Источники

### Официальные (Anthropic)

- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices — Prompting best practices
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5 — Prompting Claude Fable 5
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5 — Prompting Claude Sonnet 5
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents — Effective context engineering
- https://www.anthropic.com/research/building-effective-agents — Building Effective AI Agents
- https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents — Effective harnesses for long-running agents
- https://www.anthropic.com/engineering/how-we-contain-claude — How we contain Claude
- https://www.anthropic.com/news/enabling-claude-code-to-work-more-autonomously — Enabling Claude Code to work more autonomously
- https://www.anthropic.com/news/introducing-claude-for-education — Claude for Education
- https://claude.com/solutions/education — Education | Claude
- https://code.claude.com/docs/en/memory — How Claude remembers your project
- https://code.claude.com/docs/en/best-practices — Best practices for Claude Code
- https://code.claude.com/docs/en/skills — Skills
- https://code.claude.com/docs/en/sub-agents — Subagents
- https://code.claude.com/docs/en/hooks-guide — Hooks guide
- https://code.claude.com/docs/en/hooks — Hooks reference
- https://code.claude.com/docs/en/permissions — Permissions
- https://code.claude.com/docs/en/permission-modes — Permission modes
- https://code.claude.com/docs/en/auto-mode-config — Auto mode
- https://code.claude.com/docs/en/output-styles — Output styles
- https://code.claude.com/docs/en/headless — Headless / programmatic
- https://code.claude.com/docs/en/remote-control — Remote Control
- https://code.claude.com/docs/en/agent-view — Agent view
- https://code.claude.com/docs/en/scheduled-tasks — /loop и cron
- https://code.claude.com/docs/en/routines — Cloud Routines
- https://code.claude.com/docs/en/workflows — Dynamic workflows
- https://code.claude.com/docs/en/settings — Settings
- https://code.claude.com/docs/en/claude-directory — .claude directory
- https://code.claude.com/docs/en/changelog — Changelog
- https://code.claude.com/docs/en/discover-plugins — Plugins marketplace
- https://github.com/anthropics/claude-code/blob/main/plugins/learning-output-style/README.md — learning-output-style plugin

### Community

- https://arxiv.org/pdf/2605.10039 — Instruction Adherence in Coding Agent Configuration Files
- https://www.humanlayer.dev/blog/writing-a-good-claude-md — Writing a good CLAUDE.md
- https://github.com/anthropics/claude-code/issues/15443 — Claude ignores explicit CLAUDE.md instructions
- https://github.com/anthropics/claude-code/issues/39027 — Background task notifications trigger autonomous API calls
- https://www.aicodex.to/articles/claude-code-antipatterns — Claude Code anti-patterns
- https://www.digitalapplied.com/blog/claude-code-anti-patterns-team-adoption-failure-modes-2026 — Team adoption failure modes
- https://www.ellamind.com/blog/infra-ops-with-claude-code — Kubernetes & OpenTofu with Claude Code
- https://computingforgeeks.com/claude-code-devops-engineers/ — Claude Code for DevOps Engineers
- https://computingforgeeks.com/claude-code-terraform-guide/ — Claude Code + Terraform
- https://www.developersdigest.tech/blog/claude-code-permissions-settings-guide — settings.json permissions guide
- https://www.mindstudio.ai/blog/claude-code-monitor-tool-stop-polling-background-processes — Monitor tool
- https://www.mindstudio.ai/blog/what-is-context-rot-claude-code — Context rot
- https://wmedia.es/en/tips/claude-code-background-agents-map — Background agents map
- https://github.com/hesreallyhim/awesome-claude-code — awesome-claude-code
- https://github.com/josix/awesome-claude-md — awesome-claude-md
- https://github.com/alexknowshtml/claude-skills/blob/main/teach/SKILL.md — /teach skill
- https://mcpmarket.com/tools/skills/silver-blast-radius-assessment — Blast Radius Assessment skill
- https://learning.northeastern.edu/ai-student-guides-using-claude-learning-mode-to-study/ — Claude Learning Mode
- https://etcjournal.com/2025/11/10/review-of-kestin-et-al-s-june-2025-harvard-study-on-ai-tutoring/ — Harvard AI tutoring RCT review
- https://www.nature.com/articles/s41598-025-97652-6 — AI tutoring RCT, Scientific Reports
- https://www.funblocks.net/thinking-matters/classic-mental-models/desirable-difficulty — Desirable difficulty

Ключевые caveats research-направлений: порог «50 инструкций» — community-оценка, официально только ~200 строк; bypassPermissions при завершении фоновой задачи — открытый issue, не документированное поведение; ненаследование output style субагентами — косвенный вывод, проверить на своей конфигурации; README learning-output-style плагина расходится с актуальной документацией (считать доки авторитетнее).

---

## 7. Следующий шаг: чеклист захода №2 (по приоритету)

**High priority:**

- [ ] 1. Переписать CLAUDE.md по скелету из 4.1: двухрежимная шапка (INTERACTIVE/DELEGATED) с autonomy-блоком, секция Mentor mode 90/10 с guard-clause и keyword-override, секция Operational reflexes; Workflow пометить «(INTERACTIVE)».
- [ ] 2. settings.json: `Bash(git push:*)` из allow → ask; удалить `Bash(gh:*)`, `Bash(glab:*)` из allow; добавить в ask `Bash(gh pr create:*)`, `Bash(glab mr create:*)`.
- [ ] 3. `rm tools/claude/custom/rules/python.md` (битый симлинк).
- [ ] 4. ansible.md: убрать `**/*.yml`, `**/*.yaml` из paths, добавить ansible-специфичные глобы.
- [ ] 5. security.md: добавить frontmatter `paths:` (инфра-файлы); чеклист «When Reviewing Code» перенести в skill security-review.
- [ ] 6. Всем 6 агентам добавить read-only `tools:` (списки в 4.4).

**Medium priority:**

- [ ] 7. implement/SKILL.md: `model: sonnet` → `model: opus`.
- [ ] 8. infra-security.md: `model: sonnet` → `model: opus`.
- [ ] 9. settings.json: `fallbackModel: ["sonnet"]` → `["opus", "sonnet"]`.
- [ ] 10. read-only/SKILL.md: сузить `allowed-tools` (убрать неограниченный Bash), добавить `disable-model-invocation: true` (также в commit).
- [ ] 11. pretooluse-guard.sh: добавить secret-scan на `git add`/`git commit` (gitleaks при наличии, иначе grep-паттерны).
- [ ] 12. settings.json: prod-gate в ask (`--context=*prod*`, `--kube-context=*prod*`, `terraform workspace select prod*`).
- [ ] 13. Завести Cloud Routines: ночной cw-analyze-logs, утренний PR/MR review (без mentor-текста в промптах).

**Low priority:**

- [ ] 14. Смягчить CAPS-тон в CLAUDE.md (кроме реально критичных пунктов).
- [ ] 15. `Bash(rm:*)` из allow → ask (строгий вариант).
- [ ] 16. Разовый InstructionsLoaded-хук для проверки загрузки rules после правок paths.
- [ ] 17. Аудит 13 skills на прескриптивность под Fable 5 (outcome-формулировки вместо чек-листов); проверить отсутствие prefill/budget_tokens/CAPS-форсирования тулов в workflow-скриптах.
- [ ] 18. Проверить на одном агенте, что output style/mentor-текст действительно не наследуется субагентами.

После правок №3–5: перезапустить сессию и убедиться, что rules грузятся ожидаемо (п.16).
