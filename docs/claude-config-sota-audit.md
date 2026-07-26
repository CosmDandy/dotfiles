# Аудит конфигурации Claude Code: SOTA-практики и пробелы

**Дата:** 2026-07-26 · **Claude Code:** 2.1.220 · **Модели:** Opus 5 (основная), Fable 5, Sonnet 5

Шесть параллельных исследований: Terraform+Ansible, Kubernetes+Helm, домены без файлов (сеть/железо/VM/SSH), новые rules (shell/python/git/ci), Nix/nix-darwin, обзор возможностей Claude Code. Все выводы с источниками; спорные — перепроверены по бинарю и по живому окружению.

Цель заказчика: выжать максимум для 5-й линейки моделей и **долго не переделывать**. Отсюда рабочий принцип отчёта:

> Модельный слой (CLAUDE.md) протухает быстрее всего — за один день его переписали дважды, под Opus 4.8 и под Opus 5. Доменные правила, хуки и permissions живут годами. Значит усилия идут в долговечные слои, а модельный держим тонким.

Второй принцип, применённый ко всем правкам:

> Строка попадает в правило, только если модель **без неё ошибётся**, либо это **команда для запуска**, либо это **факт о конкретном окружении**. Учебник Opus 5 знает сам, а разбавление контекста измеримо ухудшает следование остальным правилам.

---

## TL;DR

1. **Три правила сейчас учат неверному.** `ansible.md` требует ansible-vault, тогда как архитектура на sops+age. `kubernetes.md` требует CPU-лимиты, которые в 2026 считаются вредными. `kubernetes.md` объявляет `livenessProbe` обязательным — это анти-паттерн.
2. **`updm` уничтожает возможность откатиться.** `nix-collect-garbage -d` в хвосте алиаса сносит все старые генерации; живы ровно 2. Проверено.
3. **Самый большой пробел покрытия — Nix.** Вся машина на нём, правил нет. Плюс нет правил для shell, python, git, CI — то есть для кода, который пишется чаще всего.
4. **Домены без файлов (сеть, IPMI, VM, SSH) требуют другого носителя.** Path-scoped rules там не срабатывают. Решение — три слоя: 14 строк в CLAUDE.md + 4 model-invocable скилла + PreToolUse-хук с `additionalContext`. Постоянная цена +18 строк вместо +200.
5. **Скиллы вызывает модель, а не только человек.** Описание всегда в контексте, тело подтягивается по релевантности. Это меняет ставку на скиллы как носитель.
6. **Из существующих правил примерно 40% строк — балласт.** Удаление слабых строк здесь ценнее добавления новых.
7. **Конфигурация Claude Code уже выше типовой.** Реальные пробелы: sandbox для ночных прогонов, `SessionStart`-хук, чистка мёртвой env-переменной. Остальное из «SOTA-списка» либо не подтвердилось, либо не нужно.

---

## Часть 1. Что сейчас неверно

Отсортировано по цене ошибки.

### 1.1 `ansible.md` противоречит собственной архитектуре — КРИТИЧНО

Правило говорит: `Secrets via ansible-vault only — never plaintext`.

Реальность (проверено): секреты на **sops+age**. В `docs/secrets.md:135` — `vars_plugins_enabled = community.sops.sops,host_group_vars`, файлы `group_vars/**/secrets.sops.yaml` расшифровываются автоматически; для Terraform — `TF_VAR_*` из `sops -d --extract` в `.envrc` (`:80`). Живые `ansible.cfg` есть в `~/Projects/pxe-server/ansible/` и `~/Work/kvt/infra-layer/`.

Это худший класс ошибки: правило уверенно ведёт модель в неправильную схему секретов. Замена:

```markdown
## Секреты

- Здесь секреты — sops+age, не ansible-vault: `vars_plugins_enabled = community.sops.sops,host_group_vars`
  в ansible.cfg, файлы `group_vars/**/secrets.sops.yaml` расшифровываются автоматически,
  коллекция `community.sops` — в requirements.yml. Механика целиком — docs/secrets.md
- Причина выбора: sops шифрует значения, а не файл целиком, поэтому `git diff` показывает,
  какое поле изменилось, не раскрывая значений
- ansible-vault — только там, где sops-плагин не подключён; третьего способа не изобретать
```

### 1.2 `kubernetes.md`: CPU-лимиты — совет устарел наполовину

Правило: `Resource requests and limits are MANDATORY for all containers / Set both CPU and memory`.

Консенсус 2026 разошёлся по ресурсам:

| Ресурс | Как надо | Почему |
|---|---|---|
| Память | `requests == limits` | несжимаема; разрыв даёт Burstable QoS и ранний eviction, превышение — OOMKill |
| CPU | `requests` всегда, `limits` — только при multi-tenancy/чарджбэке | CFS-квота троттлит контейнер даже на простаивающей ноде: добавляет latency, ничего не экономя |

Тим Хокин (соавтор Kubernetes) формулирует прямо: «never set CPU limits, always set memory limits equal to memory requests». Для homelab на 2×X5675 троттлинг заметнее всего.

Замена:
```markdown
- Memory: set `requests == limits` (memory is incompressible; OOMKill is worse than throttling)
- CPU: set `requests` always, `limits` only when billing/tenancy demands it — a CPU limit
  throttles via CFS quota even on an idle node
```
Побочно: строка `Missing resource requests/limits` в Common Mistakes становится противоречащей и удаляется.

Источники: [robusta.dev](https://home.robusta.dev/blog/stop-using-cpu-limits), [numeratorengineering](https://www.numeratorengineering.com/requests-are-all-you-need-cpu-limits-and-throttling-in-kubernetes/), [k8s QoS](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)

### 1.3 `kubernetes.md`: `livenessProbe — required` учит анти-паттерну

Замена:
```markdown
- `livenessProbe`: only if the process can deadlock while the port still answers. Never probe
  DB/downstream deps — a dependency outage becomes a cluster-wide restart storm
- `readinessProbe`: MAY check deps. Keep `periodSeconds*failureThreshold` lower than liveness
  so a pod can go unready before it gets killed
```
Источники: [srcco.de](https://srcco.de/posts/kubernetes-liveness-probes-are-dangerous.html), [colinbreck.com](https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-how-to-avoid-shooting-yourself-in-the-foot/)

### 1.4 `updm` делает откаты невозможными — КРИТИЧНО, не про Claude

```
… && sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +3 \
  && sudo -H nix-collect-garbage -d
```

`nix-collect-garbage -d` удаляет **все старые генерации всех профилей** в `/nix/var/nix/profiles` — официальная дока: «makes rollbacks impossible». Профиль `system` лежит там же, поэтому бережное `--delete-generations +3` обнуляется следующей командой.

Проверено: живы **2** системные генерации. То есть после каждого обновления откатываться некуда — при том что CLAUDE.md требует «знай путь отката до применения».

**Починка:** `sudo -H nix-collect-garbage --delete-older-than 7d`. Та же проблема в `updl`.

Второе: `updm` бампает lock и сразу делает `switch` **без промежуточного `build`** — механизм, которым укусил `blueutil` на свежем HEAD. Вставка `nix flake check --no-build --all-systems` или `darwin-rebuild build` оборвёт цепочку по `&&` до активации.

### 1.5 `ingress-nginx` архивирован, Ingress — legacy

Март 2026: ingress-nginx архивирован, патчей безопасности нет. Gateway API (v1.5+) — дефолт для north-south. Модель по инерции генерирует Ingress. Успешники: Envoy Gateway, Traefik, NGINX Gateway Fabric.

Источники: [Google OSS blog](https://opensource.googleblog.com/2026/02/the-end-of-an-era-transitioning-away-from-ingress-nginx.html), [k8s Steering](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/)

### 1.6 Мелкие, но реальные расхождения

| Что | Где | Починка |
|---|---|---|
| `gitleaks protect --staged` депрекейтнут с 8.19 | `tools/git/hooks/pre-commit` | `gitleaks git --pre-commit --staged` (guard и CI уже на новом синтаксисе) |
| Единственный незапиненный workflow | `.github/workflows/test-install.yml` | `actions/checkout@v4` → SHA, `ubuntu-latest` → `ubuntu-24.04` |
| `posttooluse-lint.sh` не покрывает `*.zsh`/`.zshrc` | падает в `*)` → exit 0 | добавить ветку `zsh -n` |
| `posttooluse-lint.sh` по `*.py` молча не работает | `ruff` нет в PATH, ветка гейтится на `command -v ruff` | заменить на `uvx ruff check` |
| `darwin.url = "github:LnL7/nix-darwin"` | `platform/nix/flake.nix:6` | репозиторий переехал в `nix-darwin/nix-darwin` |
| `homebrew.onActivation.cleanup = "zap"` | `darwin-configuration.nix` | касок, убранный **или закомментированный**, удаляется вместе с данными |
| `postActivation` рекурсивно `find -delete` в `/opt/homebrew/Caskroom` от root | без `-maxdepth` | добавить `-maxdepth 3` |
| `pkgs.nodejs` vs `pkgs.nodejs_24` | systemPackages vs хуки | сейчас одна версия, разъедутся — везде явный `nodejs_24` |

---

## Часть 2. Существующие правила: что менять

### 2.1 `nomad.md` — удалить

Nomad не в стеке (подтверждено заказчиком). Правило висит мёртвым грузом ровно как удалённые агенты. Восстановимо из git.

### 2.2 `terraform.md` — минус 4 секции, плюс 4

**Удалить целиком:** `## Code Structure`, `## Naming`, `## Security` (4 из 5 строк дублируют `security.md`), `## Common Mistakes` (все 5 строк — учебник; формулировка про `depends_on` «для неявных зависимостей» вообще неверна — неявные строятся сами). Также `terraform_remote_state`, `Never commit .tfstate`, `State isolation`.

**Факт окружения, который меняет всё:** `terraform` на macOS **нет** — он только в nix-профиле `devops` (Linux/DevPod). Правило должно это знать, иначе модель описывает несуществующий plan.

**Добавить:**

```markdown
## Mandatory Checks
- Валидация без креденшелов и без state: `terraform init -backend=false && terraform validate`
- `terraform plan -out=tfplan` перед apply; apply — из сохранённого плана
- `terraform fmt -recursive` (покрывает .tf/.tfvars/.tftest.hcl)
- terraform CLI есть только в nix-профиле devops (Linux/DevPod), на macOS его нет — если
  прогнать нечем, сказать это прямо, а не описывать несуществующий plan

## State и секреты
- S3-backend: `use_lockfile = true`. `dynamodb_table` deprecated с 1.11 — таблицу под локи
  в новом коде не создавать
- `sensitive = true` НЕ защищает state: значение лежит в state и в плане открытым текстом.
  Для секретов — ephemeral-переменные (1.10) и write-only аргументы (1.11)
- Секреты приходят как `TF_VAR_*` из sops через `.envrc` (docs/secrets.md) — в `*.tfvars`
  секретов не писать

## Рефакторинг и удаление
- Переезд адреса — блоком `moved` в коде, не `terraform state mv`: попадает в review.
  `moved` работает только внутри одного state
- Снять ресурс с управления, не убивая: `removed { from = … lifecycle { destroy = false } }`.
  Флаг обязателен, `true` реально удаляет. Просто вырезать блок = destroy
- План от рефакторинга должен давать 0 create/destroy

## Проверки в коде
- `check`-блоки НЕ валят apply — только warning. Должно блокировать — `precondition`/
  `postcondition` или `validation` у переменной
- `terraform test`: в `run` по умолчанию `command = apply`, то есть тест поднимает реальную
  инфраструктуру. Юнит-тест = `command = plan` + `mock_provider`
- Версии фич: check 1.5, test 1.6, removed 1.7, ephemeral 1.10, write-only 1.11.
  Сверять с `required_version`

## Операции
- `-target` — только для разгребания сбоя; после targeted apply обязателен полный plan
- Дрейф: `terraform plan -detailed-exitcode` (код 2 = расхождения)
- `.terraform.lock.hcl` коммитить с хэшами всех платформ:
  `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64 -platform=linux_arm64`
  — мак M1 + DevPod/CI на Linux, иначе `init` падает на проверке хэшей
```

**Validation Commands:** `tfsec` мёртв, все чеки переехали в Trivy. Инструментов в системе нет, но атрибуты в nixpkgs есть — звать через `nix run nixpkgs#tflint`, `nix run nixpkgs#trivy`.

**Frontmatter:** добавить `**/*.tftest.hcl`, `**/*.tfmock.hcl`, `**/*.tofu`.

### 2.3 `ansible.md` — главное: шаблонизатор 2.19

Локально **ansible-core 2.21.1**, значит ломающие изменения 2.19 уже в силе. Это самый ценный блок: класс изменений, где модель уверенно пишет **уже нерабочий** код.

```markdown
## Шаблонизация (core 2.19+)
- `when` требует boolean: `when: some_string` → «Conditionals must have a boolean result».
  Писать предикат: `| length > 0`, `is truthy`, `| bool`
- Внутри выражений нельзя `{{ }}`: `that: 1 + {{ x }} == 2` → «Template delimiters are not
  supported in expressions»
- `omit` больше не протекает из шаблонизации элемента `loop` в задачу — ставить
  `{{ item.x | default(omit) }}` на параметре задачи
- Шаблон, вернувший `None`, больше не становится пустой строкой; `range()` не выходит из
  шаблона без `| list`
- Таймаут `become` теперь unreachable-ошибка: `ignore_errors` её не поймает, нужен
  `ignore_unreachable`
- Шаблонятся только строки из доверенных источников. Строка из вывода модуля или API молча
  не рендерится — отлаживать `_ANSIBLE_TEMPLAR_UNTRUSTED_TEMPLATE_BEHAVIOR=error`
- `async_status`: `started`/`finished` больше не boolean — `until: job is finished`
```

Плюс: `uvx ansible-lint --profile production` (в системе не установлен, uvx тянет свой core 2.21); `--check` пропускает `command`/`shell`, поэтому read-only задачи помечать `check_mode: false` + `changed_when: false`; идемпотентность подтверждается **вторым прогоном** (`changed=0`), а не чтением кода. FQCN-строка сейчас буквально неверна: `ansible.builtin.*` только для встроенных, для коллекций — полное имя.

**Удалить:** `## Idempotency` кроме идеи `changed_when`, `## Naming` целиком (это правила `var-naming`/`name[casing]` в ansible-lint), `no_log` (дубль `security.md`), все 5 строк `## Common Mistakes`.

**Frontmatter:** добавить `**/*.j2` (грабли шаблонизатора живут именно там!), `**/requirements.yml`, `**/ansible.cfg`, `**/molecule/**`. Сузить `**/tasks/**` → `**/{roles,playbooks,ansible}/**/tasks/**`.

### 2.4 `kubernetes.md` — минус учебник, плюс 2026

Помимо правок из части 1:

**Удалить:** `kubectl diff`/`helm diff` (дословный дубль CLAUDE.md → Infrastructure), `kubeval` (мёртв, автор сам отправляет на kubeconform), три строки RBAC/NetworkPolicy/Secrets (дубль `security.md`, который матчит те же пути), `## Code Structure` кроме labels, `anti-affinity` (вытеснено `topologySpreadConstraints`).

**Добавить — актуальные депрекации и гочи:**
- `Endpoints` (core/v1) депрекейтнут с 1.33 → `discovery.k8s.io/v1 EndpointSlice`
- Sidecar = `initContainers` с `restartPolicy: Always` (GA с 1.33), не обычный контейнер
- `/resize` GA в 1.35 — вертикальное масштабирование без рестарта пода
- `hostUsers: false` (userns GA в 1.36) — дешёвая замена `privileged`
- PSS `restricted`: чаще всего админ-контроль валится на забытом `seccompProfile`; точка управления — **лейбл неймспейса**, не манифест
- `--dry-run=server`, не `client`: client пропускает CRD-схемы, admission и RBAC
- PDB с `minAvailable: 1` на одной реплике **блокирует drain навсегда** — критично для одноузлового homelab
- `preStop: sleep 5-10` — иначе гонка с удалением из EndpointSlices
- `whenUnsatisfiable: DoNotSchedule` + `minDomains` на малом кластере оставляет поды Pending — на homelab `ScheduleAnyway`
- cgroup v1 — hard fail kubelet с 1.35; containerd 1.x удалён в 1.36 (актуально для старого железа)
- `ValidatingAdmissionPolicy` (CEL, GA 1.30) вместо webhook; CEL не умеет сетевых вызовов — подпись образов всё равно Kyverno. `MutatingAdmissionPolicy` пока beta

**Секция Talos** (капстоун PXE → Talos → k8s):
```markdown
## Talos (this homelab)
- No SSH and no shell on nodes. Diagnostics: `talosctl -n <ip> {health,services,logs,dmesg,get,dashboard}`
  — never suggest `ssh` to a Talos node
- Node changes go through machine config: `talosctl apply-config`. sysctls, kernel args,
  kubelet flags live there, not in a DaemonSet
- Upgrades: `talosctl upgrade-k8s --to <ver>` (есть `--dry-run`), OS — `talosctl upgrade`. Не kubeadm
- Talos уже применяет PSA `baseline` кластерно и `privileged` в kube-system — privileged
  DaemonSet требует явного лейбла неймспейса
```

**Helm — секцией внутри `kubernetes.md`, не отдельным файлом.** Причина механическая: `kubernetes.md` уже матчит `**/charts/**` и `**/helm/**`, отдельный файл с теми же глобами инжектился бы вместе — экономии ноль, а расхождение появится в первый же год.
- Helm 4 актуален (ноябрь 2025), Helm 3 — только security-фиксы до начала 2027
- Переименования: `--atomic` → `--rollback-on-failure`, `--force` → `--force-replace`
- Helm 4 применяет через Server-Side Apply — конфликты field-manager теперь ошибки, это намеренно
- `values.schema.json` — единственное, что валит плохой `values.yaml` до рендера
- Чарты через OCI; `index.yaml` — legacy

**Frontmatter:** `**/*deployment*` и `**/*service*` матчат `service.go`, `deployment.tf`, systemd-юниты. Сузить до `**/*deployment*.y*ml` и т.п., добавить `**/*httproute*.y*ml`, `**/talos/**`.

---

## Часть 3. Новые правила

Шесть файлов. Все path-scoped, то есть **0 токенов постоянной стоимости** — грузятся только при работе с соответствующими файлами.

### 3.1 `nix.md` — самый большой пробел

Полное тело — в приложении A. Самое ценное (то, на чём модель гарантированно ошибётся):

- **`home/default.nix` (и значит `home.packages`) — только Linux/DevPod.** Пакет для мака идёт в `environment.systemPackages`. Правка не в том файле = no-op.
- **`nix.enable = false`** — демон принадлежит Determinate. `nix.gc`, `nix.settings`, `nix.linux-builder` **не существуют** и предлагать их нельзя.
- **PATH в activation минимален**; отсутствие бинаря даёт **молча пропущенный шаг**, не ошибку. Уже укусило дважды (`go`, `npm`).
- Activation работает под `set -eu -o pipefail`: `grep` без совпадения возвращает 1 и **обрывает все последующие хуки** — закрывать `|| true`.
- `nix flake check` без `--all-systems` **тихо пропускает 24 Linux-конфига**.
- `nix flake check` — это eval, не build. Пропавший в свежем nixpkgs пакет ловится только `nix build`.
- `darwin-rebuild switch` — прерогатива человека; агенту доступен `build`.
- На macOS home-manager — модуль nix-darwin: `home-manager switch` неверно.

### 3.2 `shell.md`

Полное тело — приложение B. Ключевое:

- **Диалект по шебангу, не по расширению.** Репозиторий смешанный: `install.sh`, `platform/**/*.sh` — zsh; хуки, `automation/**` — bash. shellcheck на zsh-файле даёт чистый шум.
- **`*.zsh`, `.zshrc` не покрыты** `posttooluse-lint.sh` — гонять `zsh -n` руками.
- **Отсутствие `set -e` в guard-хуке намеренно** и объяснено в его же комментарии: `grep` с кодом 1 не должен убивать хук. Модель иначе «починит» и **отключит защиту**.
- **ANSI в захваченном выводе** — сегодняшний шрам: `uv tool dir --bin` эмитит `\e[36m` в переменную, байты попали в путь и сломали запуск MCP. Лечится `NO_COLOR=1` + проверка `[[ -x $bin ]]`, а лучше — не парсить красивый вывод вообще.
- **nix-darwin `/etc/zshenv` перезапускает `set-environment` для каждого нового zsh** и стирает экспортированный PATH — подскрипты теряют `/opt/homebrew/bin`.
- `local x="$(cmd)"` маскирует код возврата (`local` всегда 0).
- `inherit_errexit` — иначе падение внутри `$(...)` проглатывается.

### 3.3 `python.md`

Полное тело — приложение C. Ключевое:

- **`ruff`, `mypy`, `pytest` не на PATH** — только `uv`. Значит python-ветка `posttooluse-lint.sh` **молча ничего не делает**: Python фактически не линтуется. Звать `uvx ruff` / `uv run pytest`.
- `uv run` сам локает и синкает — не может выполниться против устаревшего окружения.
- `uvx` резолвит пакет при каждом старте; для повторяющегося вызова — `uv tool install` (это уже применено к MCP-серверам).
- `uv sync --locked` валидирует свежесть лока, `--frozen` — нет.
- `mcp/timing/pyproject.toml` без `[tool.ruff]`, без тестов.
- `ty` (Astral) быстрее mypy, но pre-1.0 — не миграционная цель.

### 3.4 `git.md`

Полное тело — приложение D. Ключевое:

- **Сабмодуль хранит указатель.** Правка внутри `tools/claude/custom/` меняет его дерево, не суперпроект. Всегда два коммита.
- **`hooks.nix:152` делает `git submodule update --init` на КАЖДОЙ активации** (`updm`) — то есть откатывает сабмодуль на записанный коммит. Коммиты сабмодуля без бампа указателя выживают только в reflog. Это прямая опасность для незакоммиченных `labs/`, `skills/lab/`, `skills/c-call/`, `skills/read-only/`.
- ` m tools/claude/custom` = грязный сабмодуль → **не запускать `updm`**, пока не разрешено.
- Порядок пуша: сабмодуль → суперпроект. Проверка: `git push --recurse-submodules=check`.
- Сабмодули на `master`, суперпроект на `main`.
- PR отключены в этом репозитории — `gh pr create` даёт 404, доставка веткой.

### 3.5 `ci.md`

Полное тело — приложение E. Ключевое:

- `uvx zizmor` (безопасность) + `nix run nixpkgs#actionlint` (корректность) — оба живы в 2026 и дополняют друг друга.
- Экшены пинить по 40-символьному SHA — после компрометации tj-actions тег двигали под тысячами репозиториев.
- Никогда `${{ github.event.* }}` внутри `run:` — это инъекция на этапе раскрытия шаблона, до шелла.
- `persist-credentials: false`, если джоба не пушит.
- **Матрица:** `include:`-запись, чьи ключи отсутствуют в базовой матрице, применяется ко **всем** комбинациям — это уже задокументировано твоим же комментарием в `devcontainer-image.yml`.
- GitLab: `only/except` депрекейтнуты; `rules: changes` истинно в scheduled/tag/manual пайплайнах — всегда парой с `if:`.
- Cache poisoning: кеши ходят через границы ветвей; не восстанавливать в привилегированной джобе кеш, который может записать непривилегированная.

### 3.6 `ops-files.md` — бонус к части 4

Один path-rule на конфиги инфраструктуры (`inventory*`, `netplan/*.yaml`, `dnsmasq*.conf`, `pxelinux.cfg/**`, `*.ign`, `talconfig.yaml`, `*.utm/**`, `nftables.conf`). Покрывает 10–20% случаев — те, где работа всё-таки файловая. Тело — приложение F.

---

## Часть 4. Домены без файлов: сеть, железо, VM, SSH

**Проблема.** Path-scoped rules срабатывают, когда Claude **читает файл** по глобу. Но `ssh host 'cat /etc/netplan/01.yaml'` — это Bash, а не Read: глоб не сработает. Архитектурные обсуждения вообще не содержат tool call.

**Бюджет.** Постоянно загружено ≈210 строк (user CLAUDE.md 103 + проектный 76 + conventions 21 + MEMORY.md 13). Пять доменов прозой — это +150…250 строк, то есть удвоение постоянного контекста и просадка следования.

**Решение — три слоя, +18 строк.**

| Слой | Что | Постоянная цена |
|---|---|---|
| 1 | 14 строк в CLAUDE.md — только некомпромиссное | 14 строк |
| 2 | 4 model-invocable скилла: `ops-remote`, `ops-net`, `ops-metal`, `ops-vm` (тела 60–120 строк) | 4 строки описаний |
| 3 | PreToolUse-хук: по команде впрыскивает 5-строчный чек-лист через `additionalContext`, один раз за сессию на домен | 0 токенов |

Механика проверена по докам: `PreToolUse` официально поддерживает `additionalContext`; фильтровать по самой команде можно полем `if` с синтаксисом permission-правил. Хук — страховка на случай, если модель не выбрала скилл.

**Важная поправка к прежнему рассуждению:** скиллы вызывает не только человек. Описание всегда в контексте, тело подтягивается моделью по релевантности; `disable-model-invocation: true` как раз это ломает. Значит «я не вызываю скиллы» решается формулировкой `description` с триггерными словами, а не дисциплиной.

Артефакты (секция CLAUDE.md, хук, frontmatter скиллов) — приложение G.

### Восемь правил, которые Opus 5 нарушит без указания

1. **`ssh -o BatchMode=yes -o ConnectTimeout=5 -T`** — иначе команда вешается на `Are you sure (yes/no)` или `apt` без `-y` и съедает Bash-таймаут вместо честного падения.
2. **Одно соединение, не N** — `ControlMaster auto` + `ControlPersist`: агент делает десятки ssh-вызовов за сессию, иначе десятки KEX.
3. **Всё длиннее ~60 с — detached** (`tmux new -d`, `systemd-run --unit`). Модель кладёт `apt full-upgrade`/`dd`/прошивку в foreground, и таймаут рубит процесс **посреди записи**. Самая частая и самая дорогая ошибка.
4. **Deadman-rollback до применения**, когда правишь link/addr/route/nft/sshd на хосте, до которого дошёл по этому же пути. Модель применяет и «проверит потом» — проверять уже нечем.
5. **Baseline в файл до первого изменения**, потом по одному изменению: link → addr → route → neigh → DNS → firewall → app.
6. **DNS проверять `getent hosts`/`resolvectl query`, не `dig`** — `dig` идёт мимо nsswitch и «работает», когда приложение не резолвит. `tcpdump` — всегда с BPF-фильтром и `-c N`.
7. **BMC: ничего вслепую.** Сначала доказанная консоль (`sol info` и реально видимый вывод), потом power/bootdev/BIOS. `power soft` прежде `reset`. `bootdev` — one-shot без `options=persistent`. `mc reset cold` рвёт все сессии — не делать, пока BMC единственный вход. Пароль через `-E`/`-f`, не `-P`.
8. **Клон VM требует сброса пяти идентификаторов, не двух.** UUID и MAC известны; забываются `/etc/machine-id`, SSH host keys и cloud-init instance-id — иначе journald склеивает хосты и DHCPv6 DUID совпадает. Канонический инструмент — `virt-sysprep`.

Плюс диагностическая эвристика: **«мелочь ходит, крупное висит» = PMTUD blackhole**, а не «сеть тупит». Без подсказки модель уходит в DNS и firewall.

### Нишевое, прямо под известную боль

**`unshare --user --map-root-user --net` даёт рабочий netns без `--privileged`**: ядро проверяет `CAP_NET_ADMIN` в user-namespace, владеющем netns, а не «ты root». Снимает ограничение lab-контейнера. Оговорки: хостовые интерфейсы недоступны, `ip netns` (bind-mount в `/var/run/netns`) всё равно хочет настоящий root — проверять эмпирически.

Ещё: отдельный SSH-ключ для агента с `restrict,from=…,command=…` в `authorized_keys` — доступ отзывается и аудируется независимо от твоего; Redfish вместо IPMI там, где есть (на IMM gen1 x3550 M3 его нет — `ipmitool` корректен, но BMC-сеть держать нероутируемой).

---

## Часть 5. Claude Code: чего нет

### 5.1 Проверка спорных утверждений

Три вывода обзорного агента противоречили эмпирике — сверил по бинарю 2.1.220:

| Утверждение | Проверка | Итог |
|---|---|---|
| «sandbox-доки 404, возможно Enterprise-only» | 518 упоминаний `sandbox`, есть `allowUnsandboxedCommands`, `failIfUnavailable`, `allowedDomains` | **неверно**, фича реальна |
| «поставь плагин `security-guidance@claude-plugins-official`» | **ни одного** совпадения в бинаре | **не подтверждено**, до проверки считать выдумкой |
| «`opus[1m]` — сомнительный синтаксис» | `LN(e,t){let r=e.replace(/\[1m\]/gi,"")…}` — суффикс явно срезается перед проверкой capability | **валидно** |
| «`skipDangerousModePermissionPrompt` гасит ALL permission prompts» | гасит только предупреждение при входе в bypass-режим | **неверно и опасно** (провоцирует убрать флаг зря) |
| «удали `CLAUDE_CODE_FORK_SUBAGENT`, ты удалил сабагентов» | удалены **кастомные** определения; встроенные (Explore, general-purpose) работают и использовались для этого ресёрча | посылка ложна, **оставить** |

**Подтвердилось:** все предложенные ключи `settings.json` существуют в бинаре — `autoMode`, `classifyAllShell`, `alwaysThinkingEnabled`, `fileCheckpointingEnabled`, `additionalDirectories`, `enabledPlugins`, `disableSkillShellExecution`.

### 5.2 Реальные пробелы

| Пробел | Ценность | Долговечность |
|---|---|---|
| **Sandbox для ночных прогонов** (`sandbox.*`: filesystem/network/credentials, режим auto-allow) | высокая — единственный способ безопасно гонять автономку на личном маке; permissions описывают известные опасности, sandbox ограничивает и неизвестные | годы |
| **`SessionStart`-хук** | средняя-высокая — единственный носитель, работающий без действий человека; годится для seed'а состояния проекта | годы |
| **Cloud Routines (`/schedule`)** | средняя — прогон на инфре Anthropic вместо мака; но нужны ssh-ключи, значит не для всех задач | месяцы-годы |
| **`UserPromptSubmit`-хук** | средняя — ловит **разговор без команд** (архитектурные обсуждения), чего не может ни одно правило | годы |
| **`Stop`/`SubagentStop` с `decision: block`** | нишевая — не дать закрыть сессию, пока не снят rollback-таймер или не сделаны пост-замеры | годы |
| Topic-файлы в auto-memory | низкая-средняя — `MEMORY.md` ограничен 200 строками | годы |

### 5.3 Не трогать

Конфигурация уже выше типовой: path-scoped rules, детерминированный guard, async-линт, детальные permissions, auto-memory — всё на месте и работает. Из «привлекательного» пропустить: плагины сообщества (в основном фронтенд), Artifact-публикацию как рабочий процесс, Managed Agents, браузерный Claude Code, `autoMode` (churn-prone).

---

## Часть 6. Что сознательно отвергнуто

Чтобы было видно, что осталось за кадром намеренно:

- **Terraform Stacks** — GA, но только HCP/TFE с RUM-биллингом, недостижимо здесь.
- **Terraform 1.14 List Resources / `actions` / `terraform query`, 1.16 alpha** — устареет быстрее, чем понадобится.
- **checkov** — жив, но перекрывается с trivy; два IaC-сканера в правиле = шум.
- **terraform-docs** — жив, но генерация доков противоречит правилу «не создавать документацию без запроса».
- **terragrunt / Atlantis / Spacelift / driftctl** — не в стеке.
- **ansible-navigator + execution environments** — нужны при AAP; здесь ansible из nix напрямую.
- **HPA/VPA/KEDA, Kyverno как обязательный слой, cosign/sigstore** — для одноузлового homelab избыточно; VAP закрывает нужное.
- **Timoni / cdk8s / kpt** — ниша, Helm+Kustomize не вытеснены.
- **`polaris`, `datree`, `kubeval`, `tfsec`** — мертвы или дублируют.
- **`flake-parts` / `flake-utils`** — один darwin-конфиг, выигрыша нет.
- **`sops-nix` / `agenix`** — `docs/secrets.md` описывает **CLI**-модель (sops+age+rbw+direnv), декларативных модулей в `platform/nix/**` нет. Правило про несуществующий модуль было бы вредным.
- **`nh`, `nix-fast-build`, свой binary cache** — не установлены, своих деривейшнов нет.
- **`shfmt`/`black`/`isort`/`flake8`/`poetry`/`pyenv`** — не нужны, `ruff format` и `uv` покрывают.
- **`act`** — не воспроизводит окружение этих workflow (nix-installer, ghcr push-by-digest, arm-раннеры).
- **Учебник по shell/Python/Nix/сетям** — модель знает; строки разбавляли бы сигнал.

---

## Часть 7. План применения по приоритетам

**Приоритет 1 — исправить неверное** (мал объём, велика цена ошибки):
1. `ansible.md`: ansible-vault → sops+age.
2. `kubernetes.md`: CPU/memory лимиты, `livenessProbe`.
3. `updm`/`updl`: `nix-collect-garbage -d` → `--delete-older-than 7d`; вставить `build`/`flake check` перед `switch`.
4. `tools/git/hooks/pre-commit`: `gitleaks protect` → `gitleaks git --pre-commit --staged`.

**Приоритет 2 — покрытие** (новые правила, 0 постоянной стоимости):
5. `nix.md`, `shell.md`, `python.md`, `git.md`, `ci.md`, `ops-files.md`.
6. Удалить `nomad.md`.

**Приоритет 3 — чистка существующих правил:**
7. `terraform.md`, `ansible.md`, `kubernetes.md` — удаления и переписывания из части 2, сужение глобов.

**Приоритет 4 — домены без файлов:**
8. Секция в CLAUDE.md (14 строк) + 4 скилла + `pretooluse-opsctx.sh`.

**Приоритет 5 — Claude Code:**
9. `sandbox.*` под ночные прогоны; `SessionStart`-хук; `posttooluse-lint.sh` — ветка zsh и `uvx ruff`.

**Приоритет 6 — мелочи:** `test-install.yml` (SHA + `ubuntu-24.04`), `flake.nix` url, `-maxdepth` в postActivation, `nodejs_24` везде.

---

## Как пользоваться sandbox-профилем

`tools/claude/settings.sandbox.json` — opt-in, глобально sandbox НЕ включён. Профиль
рассчитан на локальные исследования без ssh: запись только в рабочий каталог и кеши
пакетных менеджеров, сеть по белому списку, ключи и токены закрыты.

```bash
claude --settings ~/.dotfiles/tools/claude/settings.sandbox.json
```

`--settings` — это отдельная область настроек, она **дополняет** пользовательские, а не
заменяет их: permissions и хуки остаются на месте.

Осознанные решения внутри профиля:
- `allowUnsandboxedCommands: false` — строгий режим, escape-hatch `dangerouslyDisableSandbox`
  игнорируется. Команда либо работает в песочнице, либо не работает вовсе.
- `excludedCommands: ["docker *", "orb *"]` — docker с песочницей несовместим по документации.
- `credentials.files` закрывает `~/.ssh`, `~/.aws`, `~/.kube`, `~/.config/sops` и конфиги
  `gh`/`glab`; `envVars` снимает токены. Встроенного deny-списка нет — закрыто только то,
  что перечислено явно.
- Go-бинари (`gh`, `gcloud`, `terraform`) под Seatbelt могут падать на проверке TLS. Если
  понадобятся в песочнице — добавлять в `excludedCommands`, помня, что это снимает изоляцию
  именно с них.

Для инфраструктурных задач, которым нужен ssh, песочница — неподходящий инструмент: дырявить
её под ключи значит терять смысл. Там слой изоляции — devcontainer плюс отдельный ssh-ключ,
ограниченный через `authorized_keys` (`restrict,from=…,command=…`).

## Верификация

Обязательные проверки после применения:

- [ ] **Открытый вопрос:** грузятся ли user-scope правила безусловно, независимо от `paths:`? Проверить `/context` в **чистой** сессии. Если да — весь расчёт бюджета меняется, и часть правил надо переносить в project-scope. (Наблюдение агента: `security.md` попал в контекст сессии без чтения `.tf`. Вероятное объяснение — на старте сессии у файла ещё не было frontmatter. Требует подтверждения.)
- [ ] Каждое новое правило: `/memory` показывает его загрузку при открытии соответствующего файла и **не показывает** при открытии несвязанного.
- [ ] Глобы не перематчивают: открыть `service.go`, обычный `.yml`, `pyproject.toml` вне python-проекта — правила не всплывают.
- [ ] `nix flake check --no-build --all-systems` после правки `flake.nix`.
- [ ] `bash -n` + `shellcheck` для новых хуков; функциональный тест guard-хука синтетическим PreToolUse-входом.
- [ ] `updm` после правки: `sudo darwin-rebuild --list-generations` показывает больше двух.
- [ ] Смоук ops-слоя: команда с `ssh` в новой сессии — хук впрыскивает контекст один раз, не тридцать.

---

## Приложения

Полные тела правил и артефактов лежат в выводах исследований этой сессии; при применении они вставляются как есть:

- **A** — `nix.md` (готов, прогнан `nix flake check`/`statix`/`deadnix` на живой машине)
- **B** — `shell.md`
- **C** — `python.md`
- **D** — `git.md`
- **E** — `ci.md`
- **F** — `ops-files.md`
- **G** — секция CLAUDE.md «Ops domains», `hooks/pretooluse-opsctx.sh`, frontmatter четырёх `ops-*` скиллов

---

## Источники

**Terraform / Ansible:** [s3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) · [state sensitive data](https://developer.hashicorp.com/terraform/language/state/sensitive-data) · [ephemeral 1.11](https://www.hashicorp.com/en/blog/terraform-1-11-ephemeral-values-managed-resources-write-only-arguments) · [tests](https://developer.hashicorp.com/terraform/language/tests) · [moved/refactoring](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) · [removed block](https://support.hashicorp.com/hc/en-us/articles/34185721057555-Removing-a-Resource-from-the-Terraform-State-Using-the-removed-block) · [-target](https://support.hashicorp.com/hc/en-us/articles/46733517346451-Understanding-and-Safely-Using-the-target-option-in-HCP-Terraform) · [providers lock](https://developer.hashicorp.com/terraform/cli/commands/providers/lock) · [tfsec→Trivy](https://appsecsanta.com/iac-security-tools/tfsec-vs-trivy) · [porting guide 2.19](https://docs.ansible.com/projects/ansible-core/devel/porting_guides/porting_guide_core_2.19.html) · [porting guide 2.20](https://docs.ansible.com/projects/ansible-core/devel/porting_guides/porting_guide_core_2.20.html) · [ansible-lint profiles](https://docs.ansible.com/projects/lint/profiles/) · [check mode](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html) · [Molecule](https://docs.ansible.com/projects/molecule/workflow/)

**Kubernetes / Helm:** [CPU limits](https://home.robusta.dev/blog/stop-using-cpu-limits) · [requests are all you need](https://www.numeratorengineering.com/requests-are-all-you-need-cpu-limits-and-throttling-in-kubernetes/) · [QoS](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/) · [liveness probes are dangerous](https://srcco.de/posts/kubernetes-liveness-probes-are-dangerous.html) · [probes footguns](https://blog.colinbreck.com/kubernetes-liveness-and-readiness-probes-how-to-avoid-shooting-yourself-in-the-foot/) · [disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) · [PDB pitfalls](https://www.chkk.io/blog/pod-disruption-budgets) · [topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) · [PSS](https://kubernetes.io/docs/concepts/security/pod-security-standards/) · [native sidecars](https://kubernetes.io/blog/2023/08/25/native-sidecar-containers/) · [in-place resize GA](https://kubernetes.io/blog/2025/12/19/kubernetes-v1-35-in-place-pod-resize-ga/) · [userns GA](https://kubernetes.io/blog/2026/04/23/kubernetes-v1-36-userns-ga/) · [Endpoints deprecation](https://kubernetes.io/blog/2025/04/24/endpoints-deprecation/) · [ingress-nginx statement](https://www.kubernetes.io/blog/2026/01/29/ingress-nginx-statement/) · [Gateway API v1.5](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5/) · [VAP + CEL](https://www.systemshardening.com/articles/kubernetes/validating-admission-policy-cel/) · [kubeconform](https://github.com/yannh/kubeconform) · [Helm 4](https://helm.sh/blog/helm-4-released/) · [Helm 3 EOL](https://helm.sh/blog/helm-v3-end-of-life/) · [Talos: no shell](https://alexandre-vazquez.com/talos-linux-guide/) · [Sidero Pod Security](https://docs.siderolabs.com/kubernetes-guides/security/pod-security)

**Nix:** [flake check](https://nix.dev/manual/nix/2.30/command-ref/new-cli/nix3-flake-check.html) · [nix-darwin](https://github.com/nix-darwin/nix-darwin/blob/master/README.md) · [release-branch check #1284](https://github.com/nix-darwin/nix-darwin/issues/1284) · [Determinate + nix-darwin](https://docs.determinate.systems/guides/nix-darwin/) · [GC: -d makes rollbacks impossible](https://nixos.org/manual/nix/stable/package-management/garbage-collection) · [homebrew cleanup option](https://mynixos.com/nix-darwin/option/homebrew.onActivation.cleanup) · [nix-darwin #1787](https://github.com/nix-darwin/nix-darwin/issues/1787) · [nixfmt RFC 166](https://github.com/NixOS/nixfmt) · [mkOutOfStoreSymlink #1808](https://github.com/nix-community/home-manager/issues/1808)

**Shell / Python / Git / CI:** [BashFAQ 105](https://mywiki.wooledge.org/BashFAQ/105) · [SC2155](https://www.shellcheck.net/wiki/SC2155) · [no-color.org](https://no-color.org/) · [uv tools](https://docs.astral.sh/uv/guides/tools/) · [uv sync](https://docs.astral.sh/uv/concepts/projects/sync/) · [PEP 735](https://peps.python.org/pep-0735/) · [ruff formatter](https://docs.astral.sh/ruff/formatter/) · [ty](https://astral.sh/blog/ty) · [Git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) · [gitleaks releases](https://github.com/gitleaks/gitleaks/releases) · [zizmor](https://docs.zizmor.sh/integrations/) · [actions static analysis](https://ddbeck.com/notes/more-github-actions-static-analysis-tools/) · [SHA pinning](https://www.stepsecurity.io/blog/pinning-github-actions-for-enhanced-security-a-complete-guide) · [secure use of Actions](https://docs.github.com/en/actions/reference/security/secure-use) · [cache poisoning](https://adnanthekhan.com/2024/05/06/the-monsters-in-your-build-cache-github-actions-cache-poisoning/) · [GitLab deprecated keywords](https://docs.gitlab.com/ci/yaml/deprecated_keywords/) · [rules:changes](https://docs.gitlab.com/ci/yaml/#ruleschanges)

**Ops / сеть / железо:** [ssh_config](https://man.openbsd.org/ssh_config) · [user namespaces](https://ericchiang.github.io/post/user-namespaces/) · [unprivileged netns](https://blog.0x1b.me/posts/unprivileged-linux-netns-pt1/) · [cloning VMs (Red Hat)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_virtualization/cloning-virtual-machines_configuring-and-managing-virtualization) · [PMTUD blackhole](https://oneuptime.com/blog/post/2026-03-20-fix-black-hole-pmtud-failure/view) · [BMC reset](https://support.exxactcorp.com/hc/en-us/articles/31728599437847-Resetting-the-BMC-Using-ipmitool-on-Linux)

**Claude Code:** [hooks](https://code.claude.com/docs/en/hooks) · [memory](https://code.claude.com/docs/en/memory) · [skills](https://code.claude.com/docs/en/skills) · [sandboxing](https://code.claude.com/docs/en/sandboxing) · [routines](https://code.claude.com/docs/en/routines) · [output styles](https://code.claude.com/docs/en/output-styles) · [settings](https://code.claude.com/docs/en/settings)
