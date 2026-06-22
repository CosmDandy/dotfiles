# Dotfiles + Claude Code: ресёрч и план улучшений (2026-06-18)

> Синтез по 11 темам с проверкой источников (verdicts) + приоритизированный аудит конфига.
> Источники истины для Claude Code — **code.claude.com/docs** (не docs.anthropic.com, домен переехал; индекс: code.claude.com/docs/llms.txt).
> Профиль: nix-darwin (M1) + DevPod/Linux, монорепо dotfiles, Claude Code с 3-слойной системой (rules/agents/skills), MCP, ~200 allow / ~60 deny permissions, только Stop-хук.

---

## 1. Executive summary

Конфиг пользователя сильный, но недозадействует две вещи, которые в 2026 стали стандартом: **расширенные hooks** (сейчас только Stop=bell, а доступно ~30 событий с детерминированным enforcement) и **шифрование секретов** (plaintext `.env` с реальными токенами JIRA/GitLab/Nomad/OpenSearch, только gitignore). Это прямые нарушения собственного `security.md`. Топ-приоритет — закрыть оба: PreToolUse/PostToolUse/SessionStart хуки + SOPS+age для `.env`/`private/`, плюс CI-тест идемпотентности `install.sh`.

Управление Mac с телефона в 2026 решается тремя слоями: нативный **Remote Control** (за NAT без проброса портов, но не полный шелл), **Cloud Routines** (облачные расписания/GitHub-webhook) и community-связка **Tailscale+SSH+tmux** (полный шелл с dangerous permissions). Критично: установленные `DISABLE_TELEMETRY=1` и `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` **отключают /schedule и Routines** и могут гейтить eligibility Remote Control — нужна отдельная обёртка запуска без этих флагов.

Claude Desktop стал единым приложением (Chat/Cowork/Code) и читает тот же `~/.claude/settings.json`/CLAUDE.md/skills/MCP — весь dotfiles-сетап переносится без работы. DevPod остаётся лучшим open-source CDE; официальная Anthropic devcontainer-feature + named volume + containerEnv делают встраивание Claude в контейнер воспроизводимым.

По экосистеме: для greenfield IaC — OpenTofu (state encryption), policy-as-code — Kyverno (CNCF graduated 24.03.2026) + CEL, supply-chain — cosign keyless + SLSA L2, K8s baseline — 1.35/1.36 (1.33 EOL 28.06.2026), Gateway API вместо ingress-nginx (retired). Homelab-канон — onedr0p/cluster-template (Talos+Flux+Cilium+SOPS+age) на мини-ПК N150/N305 — ровно под существующую экспертизу пользователя. Секреты-индустрия: OpenBao (MPL) как control plane, dynamic secrets, OIDC keyless в CI, ESO/VSO + SOPS+age в GitOps.

CLI: база уже сильная (eza/fd/ripgrep/atuin/yazi/lazygit/k9s/btop + zinit с autosuggestions/fast-syntax-highlighting). **Реальные пробелы** (после сверки конфигов, опровергнувшей часть исходных предположений): нет `bat`, `zoxide`, `fzf`, `delta`, опционально `mise`. zoxide+fzf+fzf-tab — наибольший ROI.

Важно про достоверность: ряд исходных тезисов опровергнут при сверке с репо — у пользователя **уже стоят** zinit + autosuggestions + fast-syntax-highlighting + zsh-completions (а не отсутствуют), а `delta` наоборот **отсутствует** (вопреки предположению). Часть статистики и атрибуций к источникам помечена ниже как `[partly]`/`[refuted]`.

---

## 2. Находки по темам

Легенда: `[freshness/confidence]`, вердикт проверки в скобках — `confirmed` / `partly` / `refuted` / `unverifiable`.

### 2.1. Управление Mac с телефона через Claude Code

- **Native Remote Control** [high/2026, confirmed]: локальная сессия управляется с телефона/браузера, код остаётся на машине. `claude remote-control` (server mode, до 32 сессий, `--capacity`, `--spawn`), `claude --rc`, `/rc` в сессии (переносит историю), `/mobile` (QR). Включить для всех: `/config → Enable Remote Control for all sessions`. Требует v2.1.51+ (VS Code v2.1.79+), **claude.ai OAuth** (API-ключи/setup-token НЕ работают). Только исходящий HTTPS:443, **нет входящих портов** — работает за NAT/файрволом без VPN. [Remote Control](https://code.claude.com/docs/en/remote-control)
- **Ограничения Remote Control** [high/2026, confirmed]: терминал должен оставаться открытым, таймаут ~10 мин без сети, Ultraplan отключает RC. Текстовые команды (`/compact`, `/clear`, `/context`, `/usage`, `/mcp`) работают с телефона, интерактивные (`/plugin`, `/resume`) — нет. Push: v2.1.110+. Показывает диалог Claude, **не raw-терминал** — для произвольных команд нужен SSH+tmux. [Remote Control](https://code.claude.com/docs/en/remote-control)
- **Claude Code on the web** [high/2026, confirmed]: облачные сессии (отдельно от RC), переживают закрытие браузера, нужен GitHub-доступ. `--remote` создаёт облачную сессию, `--teleport` втягивает в терминал (handoff односторонний). Делит rate limits аккаунта. [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
- **Routines** [high/2026-04, confirmed; дата запуска 14.04.2026 — partly/unverifiable из primary doc]: облачная автоматизация. Триггеры: Schedule (мин. 1 час, кастомный cron через `/schedule update`), API (`POST /v1/claude_code/routines/{id}/fire`, beta-заголовок `experimental-cc-routine-2026-04-01`), GitHub event (только **Pull request + Release**, требует Claude GitHub App; `/web-setup` даёт только клон). Исполняются в облаке (нет локальных файлов). [Routines](https://code.claude.com/docs/en/routines)
- **КРИТИЧНО** [high/2026, confirmed]: `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK` отключают fetch feature-флагов → `/schedule` скрывается, Routines не работают, может гейтить eligibility RC. У пользователя стоят **оба** ключевых флага. [Routines](https://code.claude.com/docs/en/routines)
- **Tailscale + SSH/mosh + tmux** [high/2026-02-08, confirmed как community-практика]: основной способ полного шелл-контроля (включая dangerous permissions). Claude в tmux на Mac, телефон attach-ится, переживает обрывы. Tailscale (WireGuard, free до 100 устройств) пробивает NAT без проброса портов. [samwize: control your Mac safely](https://samwize.com/2026/02/08/control-your-mac-from-your-iphone-safely-tailscale-ssh-tmux/)
- **Грабли SSH на macOS** [high/2026]: файрвол блокирует Remote Login; Mac засыпает (Amphetamine/caffeinate); mosh часто не нужен (Tailscale держит соединение). [Termius+iPhone+Claude](https://zenn.dev/shimo4228/articles/termius-iphone-claude-code?locale=en)
- **iOS SSH-клиенты** [medium/2026]: Blink Shell — лучший для resilience (нативный mosh), Termius — кросс-платформенность. [Best mobile SSH 2026](https://onepilotapp.com/blog/best-mobile-ssh-app-2026)
- **Headless** [medium/2026]: `claude -p` + launchd (нативнее cron на M1) для расписаний с локальным доступом к файлам. [Headless mode](https://www.mindstudio.ai/blog/claude-code-headless-mode-autonomous-agents)
- **Self-hosted GUI** [medium/2026]: siteboon/claudecodeui (CloudCLI), Orca — без зависимости от research-preview фич. [claudecodeui](https://github.com/siteboon/claudecodeui)

### 2.2. Claude Desktop и Cowork

- **Три вкладки** [high/2026, confirmed, дословно]: «Chat for conversations, Cowork for Dispatch and longer agentic work, and Code for software development». Code-вкладка = тот же движок Claude Code с GUI, читает те же `settings.json`/CLAUDE.md/skills/hooks/MCP. [Desktop](https://code.claude.com/docs/en/desktop)
- **Cowork** [high/2026, partly]: GA 09.04.2026 (preview 12.01.2026 — на старте только Max, Pro с 16.01; не «все платные»). macOS+Windows, **Linux нет** (только CLI). Окно держать открытым. Windows Home не тянет (нужен Hyper-V — деталь из community-issues, не с anthropic.com). [Cowork](https://www.anthropic.com/product/claude-cowork)
- **Dispatch** [high/2026, confirmed]: персистентный разговор в Cowork; dev-задачи спавнятся как Code-сессия с бейджем Dispatch, research остаётся в Cowork. Требует Pro/Max (не Team/Enterprise). [Desktop](https://code.claude.com/docs/en/desktop)
- **MCP/коннекторы** [high/2026]: Desktop читает CLI-конфиги (`~/.claude.json`, `.mcp.json`). Caveat: MCP, добавленный через Desktop-чат (`claude_desktop_config.json`), standalone CLI не видит — нужен `claude mcp add-from-claude-desktop`. [Desktop](https://code.claude.com/docs/en/desktop)
- **Чего нет в Desktop** [high/2026]: нет scripting (`--print`, Agent SDK/headless), terminal-команд (`/permissions`, `/config`, `/agents`, `/doctor` — правь settings напрямую). [Desktop](https://code.claude.com/docs/en/desktop)
- **Code-вкладка** [high/2026]: worktree-изоляция параллельных сессий (`<repo>/.claude/worktrees/`), preview, PR-мониторинг через gh с auto-merge=squash (совпадает с `shared/conventions.md`). Окружения Local/Remote(cloud)/SSH. [Desktop](https://code.claude.com/docs/en/desktop)
- Computer use, Auto/Bypass mode — research preview, Pro/Max, off по умолчанию [high/2026]. Cowork без ревью иногда правит файлы — бэкап + узкий allow [medium/2026, сторонние обзоры]. [Cowork guide](https://www.ai.cc/blogs/how-to-use-claude-cowork-2026-step-by-step-guide/)

### 2.3. Продвинутые возможности Claude Code

- **Hooks: ~30 событий** [high/2026, partly — содержание confirmed, цифра «35» завышена, реально ~30]: SessionStart, Setup, SessionEnd, UserPromptSubmit, Stop, PreToolUse, PostToolUse, PermissionRequest, SubagentStart/Stop, FileChanged, CwdChanged, WorktreeCreate/Remove и др. У пользователя — только Stop(bell). [Hooks](https://code.claude.com/docs/en/hooks)
- **5 типов хендлеров** [high/2026, confirmed]: command, http, mcp_tool, prompt, agent + флаги `async`/`asyncRewake`. [Hooks](https://code.claude.com/docs/en/hooks)
- **PreToolUse переписывает вход** [high/2026, partly]: `updatedInput` (v2.0.10+), `permissionDecision` allow/deny/ask (есть и `defer`). PostToolUse: `updatedToolOutput` (v2.1.121+). `continueOnBlock` — в сторонних гайдах, **официально не подтверждён**. exit code 2 = блокирующая ошибка; для Stop проверять `stop_hook_active`. [Hooks](https://code.claude.com/docs/en/hooks)
- **SessionStart + CLAUDE_ENV_FILE** [high/2026, confirmed]: пишешь `export VAR=...` → доступно всем Bash-командам сессии. Прямой ответ на пробел с OpenSearch-кредами. [Hooks](https://code.claude.com/docs/en/hooks)
- **Stop в frontmatter агента → SubagentStop** [confirmed официальной докой; атрибуция к morphllm refuted, версия v1.0.41+ unverifiable]: «For subagents, Stop hooks are automatically converted to SubagentStop». [Hooks](https://code.claude.com/docs/en/hooks)
- **Skills = slash commands** [high/2026, confirmed]: skills — рекомендуемый формат, при коллизии имён skill побеждает; пустой `commands/` — норма. Скилл рендерится в контекст один раз при вызове. [Skills](https://code.claude.com/docs/en/skills)
- **Планировщики** [high/2026, confirmed]: `/loop` + cron-tools (v2.1.72+, только пока сессия открыта); Cloud Routines (облако, мин. 1ч); Desktop tasks (локально, мин. 1мин, **нет на Linux**). [Scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks)
- **Git worktrees в CLI** [high/2026, confirmed, v2.1.50]: `claude --worktree`, `isolation: worktree` в frontmatter агента. Добавить `.claude/worktrees/` в gitignore. [Worktrees](https://code.claude.com/docs/en/worktrees)
- **Dynamic Workflows** [high/2026-05-28]: до 1000 сабагентов, JS-оркестрация в фоне (`ultracode`/effort=xhigh). Жрёт токены — начинать со scoped. [Dynamic Workflows](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code)
- **/goal** [medium/2026-05, v2.1.139+]: работа до выполнения условия, evaluator (Haiku) после каждого хода. [Goal](https://code.claude.com/docs/en/goal)
- **/output-style удалён** (v2.1.91) [high/2026, confirmed]: фича жива, но настройка только через `/config` или поле `outputStyle`. Проверить install.sh на вызовы удалённой команды. [Output styles](https://code.claude.com/docs/en/output-styles)
- **settings.json** [medium/2026]: добавить `$schema`; `attribution`-объект заменил deprecated `includeCoAuthoredBy`. [Settings misc](https://blog.vincentqiao.com/en/posts/claude-code-settings-misc/)
- **Statusline** [high/2026, confirmed, v2.1.153+]: `COLUMNS`/`LINES` в env, `output_style` в JSON-пейлоаде. [Statusline](https://code.claude.com/docs/en/statusline)
- **Channels** [medium/2026-03, v2.1.80+]: пуш-события из Telegram/Discord в живую сессию. [Channels](https://code.claude.com/docs/en/channels)

### 2.4. Организация dotfiles (2026)

- **chezmoi** [high/2026, confirmed]: single binary, шаблоны, whole-file шифрование (age/gpg), password managers, реальные файлы (не симлинки). [chezmoi comparison](https://www.chezmoi.io/comparison-table/)
- **Stow/dotbot** [high/2024-12, confirmed]: чистые symlink-менеджеры без шаблонов/секретов; уйти от Stow тяжело. [Tools for dotfiles](https://gbergatto.github.io/posts/tools-managing-dotfiles/)
- **Секреты 2026** [high/2026-03, partly — суть confirmed, атрибуция к dotfiles.io частична]: age (whole-file) + SOPS+age (field-level, диффабельно) — стандарт; git-crypt легаси (бинарные диффы). [dotfiles secret management](https://dotfiles.io/en/guides/secret-management/), [NixOS secrets overview](https://discourse.nixos.org/t/handling-secrets-in-nixos-an-overview-git-crypt-agenix-sops-nix-and-when-to-use-them/35462)
- **Bootstrap идемпотентность + CI** [high/паттерн актуален, confirmed]: двойной прогон в одном job (1й — установка, 2й — идемпотентность), matrix по ОС. [Testing my dotfiles](https://tomforb.es/blog/testing-my-dotfiles/)
- **Вывод**: гибрид пользователя (nix-darwin + bash install.sh + симлинки + DevPod) рабочий. Не мигрировать на chezmoi; закрыть два пробела — шифрование секретов и CI install.sh.

### 2.5. Nix / nix-darwin / home-manager / flakes

- **Единый flake** [high/2026, confirmed]: `home-manager.inputs.nixpkgs.follows = "nixpkgs"` (и для nix-darwin), `useGlobalPkgs=true`, `useUserPackages=true`. [Home Manager Manual](https://nix-community.github.io/home-manager/)
- **Три способа HM; для не-NixOS Linux только standalone** [high/2026, confirmed]: на macOS — модуль nix-darwin, на Linux (DevPod) — standalone из того же flake. [Home Manager Manual](https://nix-community.github.io/home-manager/)
- **HM = всегда симлинки** [confirmed]: `home.file`/`xdg.configFile` → /nix/store; `mkOutOfStoreSymlink` → живой файл в репо (правки без ребилда, аналог stow/chezmoi). С flakes нужен абсолютный строковый путь. [HM dotfiles](https://gvolpe.com/blog/home-manager-dotfiles-management/)
- **mutable/immutable toggle** [medium/2025-09, confirmed]: `dotfiles.mutable` + `mkOutOfStoreSymlink`, массово через `builtins.mapAttrs`. [HN 45421485](https://news.ycombinator.com/item?id=45421485)
- **Структура multi-OS** [high/2025-2026]: flake-parts + dendritic + import-tree, модули по фиче а не по ОС (для 1 Mac + контейнеров — оверкилл). [nix-config example](https://github.com/AlexNabokikh/nix-config)
- **macOS-гигиена** [high/2024-2025]: перед апгрейдом macOS — Determinate `repair sequoia --move-existing-users`; при ошибках /etc — `.before-nix-darwin`. [Determinate: macOS Sequoia](https://determinate.systems/blog/nix-support-for-macos-sequoia/)
- **devShells/devenv + cachix** [high/2026]: воспроизводимые dev-окружения, ускорение сборок. [devenv+flake-parts](https://devenv.sh/guides/using-with-flake-parts/), [Cachix 1.10](https://blog.cachix.org/posts/2026-01-28-cachix-deploy-ga-and-cachix-1-10/)

### 2.6. DevPod / devcontainers

- **DevPod** [high/2026, confirmed]: client-only open-source CDE на devcontainer.json, провайдеры docker/k8s/ssh/aws/gcp/azure. [DevPod](https://github.com/loft-sh/devpod)
- **Стабильного v0.7 нет** [high/2026-06, confirmed]: последняя v0.7.0-alpha.34 (июнь 2026); для прода держаться v0.6.x. [Releases](https://github.com/loft-sh/devpod/releases)
- **Prebuilds** [high/2025-2026, confirmed]: хэш devcontainer.json → тег образа; `devpod build --repository`; `customizations.devpod.prebuildRepository`. [Prebuild](https://devpod.sh/docs/developing-in-workspaces/prebuild-a-workspace)
- **dotfiles в DevPod** [high/2025, confirmed]: `--dotfiles` + автодетект install.sh (первым в списке), глобально `DOTFILES_URL`. Caveat: приватный/SSH-репо → auth-баги, обход HTTPS. [Dotfiles in workspace](https://devpod.sh/docs/developing-in-workspaces/dotfiles-in-a-workspace)
- **Claude в devcontainer** [high/2026, confirmed]: официальная feature `ghcr.io/anthropics/devcontainer-features/claude-code:1.0` + named volume для `~/.claude` + ENV в containerEnv. MCP — через project-scope `.mcp.json`. [Devcontainer](https://code.claude.com/docs/en/devcontainer)
- **Безопасный автономный режим** [high/2026]: `--dangerously-skip-permissions` только non-root + firewall egress allowlist (init-firewall.sh, NET_ADMIN/NET_RAW). Не монтировать `~/.ssh`/cloud-креды. [Devcontainer](https://code.claude.com/docs/en/devcontainer)
- **Рынок CDE** [medium/2026-04]: Gitpod→Ona, Daytona→AI-sandbox; остались Codespaces (managed) и Coder (self-hosted). DevPod + Nix — durable выбор. [Codespaces alternatives](https://www.bunnyshell.com/comparisons/github-codespaces-alternative/)
- **Nix devshell** [high/2026]: безконтейнерная альтернатива на macOS (нет оверхеда виртуализации x86). [Nix dev environments](https://nixos-and-flakes.thiscute.world/development/dev-environments)

### 2.7. DevOps / Platform Engineering

- **OpenTofu** [medium/2026, confirmed по фичам, partly по статистике]: client-side state encryption (1.7, AES-GCM + KMS/Vault, необратимо для TF), provider-defined functions, early variable evaluation (1.8), ephemeral resources/write-only/enabled (1.11). Доля ~12%, TF лидирует. [OpenTofu vs Terraform 2026](https://jorijn.com/en/blog/opentofu-vs-terraform-2026-the-fork-finally-diverged/), [OpenTofu 1.7 state encryption](https://opentofu.org/blog/opentofu-1-7-0/)
- **Platform as a Product** [medium/2026, confirmed]: Gartner — 80% крупных org к 2026 (было 45% в 2022); Backstage ~89% доли, но дорог (TCO ~$150k/20 dev). [PE in 2026](https://roadie.io/blog/platform-engineering-in-2026-why-diy-is-dead/)
- **Crossplane v2 / Kratix** [medium/2026, confirmed]: v2 убрал Claims, XR namespaced + RBAC; v2.2 (фев 2026) Pipeline Inspector + CEL-валидация. [Crossplane v2.2 deep dive](https://dev.to/x4nent/crossplane-v22-deep-dive-pipeline-inspector-cel-validation-and-production-control-planes-1ed9)
- **Kyverno graduation** [high/2026-03-24, confirmed]: CNCF graduated 24.03.2026; оба движка policy-as-code сходятся к CEL (Kyverno 1.17, Gatekeeper 3.22). Гибрид: Kyverno для K8s-native, OPA для cross-stack. [Kyverno graduation](https://cloudnativenow.com/kubecon-cloudnativecon-europe-2026/cncf-announces-kyverno-graduation-as-policy-as-code-adoption-grows/)
- **eBPF / OBI** [high/2026-04]: 67% prod-кластеров уже на eBPF observability; OBI (преемник Beyla, beta апр 2026) для L7; Tetragon — runtime security; Hubble — network flows. Caveat: на Cilium/Calico eBPF-dataplane ставить OBI `network.enabled:false`. [OBI guide KubeCon EU 2026](https://dev.to/x4nent/opentelemetry-ebpf-instrumentation-obi-the-complete-guide-kubecon-eu-2026-beta-launch-5e2o)
- **Supply-chain** [medium/2026]: >454,600 новых вредоносных пакетов 2025 (99% npm); SBOM+SLSA+Sigstore/Cosign дополняют друг друга; цель SLSA L2 как минимум (достижимо в GitHub Actions). [Supply chain signing/SLSA](https://aquilax.ai/blog/supply-chain-artifact-signing-slsa)
- **Агентный AIOps** [medium/2026-04]: MCP — стандарт интеграции агентов; AWS DevOps Agent GA; kagent (агенты как CRD); паттерн read-first/act-second + approval gates. [AWS DevOps Agent GA](https://www.infoq.com/news/2026/04/aws-devops-agent-ga/)
- **Замечание о достоверности**: «>64% enterprise используют GitOps как primary delivery» — **refuted** как CNCF-факт (реально: 64% относится к ease-of-use; primary delivery — иные цифры). HCP Terraform free tier — закрыт только legacy plan, не полностью. CNCF принял OpenTofu на уровне sandbox.

### 2.8. Kubernetes-экосистема

- **Версии** [high/2026-05, confirmed]: stable 1.36.1; 1.33 EOL **28.06.2026**, 1.34 — 27.10.2026. Baseline в rules → 1.35/1.36. [K8s releases](https://kubernetes.io/releases/)
- **In-Place Resize GA 1.35; DRA GA 1.34** [high, confirmed]. [v1.34 release](https://kubernetes.io/blog/2025/08/27/kubernetes-v1-34-release/)
- **Security/DX 1.34** [high, partly]: SA-токены для image credential providers (beta), mTLS pod→apiserver (alpha), CEL mutating admission (beta, не alpha), KYAML (alpha). [v1.34 release](https://kubernetes.io/blog/2025/08/27/kubernetes-v1-34-release/)
- **Gateway API** [high/2026, partly]: v1.4 GA (окт 2025), уже v1.5 GA (фев 2026); ingress-nginx retired (~март 2026, точная дата 31.03 unverifiable); Ingress API НЕ депрекейтнут. Конформны: Cilium, Istio, Contour, Traefik v3, Envoy Gateway, HAProxy. [ingress-nginx → Gateway API](https://www.okteto.com/blog/ingress-nginx-controller-deprecation-your-migration-guide-to-kubernetes-gateway-api/)
- **Cilium 1.19** [high/2026-02]: strict IPsec/WireGuard, kube-proxy replacement (kernel ≥5.10). Caveat: socket-LB ломает NFS/SMB RWX на ClusterIP. [Cilium 1.19](https://www.infoq.com/news/2026/02/cilium-119/)
- **PSS via Kyverno** [high/2026, confirmed]: профиль на кластер одним правилом + exempt по образам, поверх нативного PSA. [Kyverno pod security](https://kyverno.io/docs/guides/pod-security/)
- **AI/ML на k8s** [medium/2026]: KServe LLMInferenceService + vLLM + KubeRay + Kueue. [AI/ML on K8s 2026](https://kubernetesguru.com/ai-ml-on-kubernetes-2026-stack-guide/)
- **Cost/rightsizing** [medium/2026]: связка VPA/KRR + Karpenter + HPA; антипаттерн VPA+HPA на одной метрике. [Rightsizing 2026](https://leanopstech.com/blog/kubernetes-rightsizing-vpa-hpa-krr-karpenter-2026/)
- **Homelab K8s** [medium/2025-03]: Talos (immutable) vs k3s (single binary); k0s third option. [Homelab K8s distros](https://www.virtualizationhowto.com/2025/03/best-kubernetes-distributions-for-home-lab-enthusiasts-in-2025/)

### 2.9. Vault / управление секретами

- **OpenBao** [high/2025-2026, confirmed]: функционально идентичный форк Vault (MPL 2.0, LF Edge), отличие — лицензия (Vault на BUSL 1.1, IBM купил HashiCorp $6.4B 27.02.2025). OpenBao 2.5.0 (фев 2026) — Namespaces + Horizontal Read Scalability в open source; гэп — DR/Performance Replication. [Vault vs OpenBao](https://digitalis.io/post/choosing-a-secrets-storage-hashicorp-vault-vs-openbao)
- **Dynamic secrets** [high, confirmed]: short-TTL креды (БД/cloud/PKI/EaaS); HCP Vault Secrets EOL 01.07.2026 (PAYG раньше — 27.08.2025); Community Edition бесплатна. [Vault secrets management](https://sjramblings.io/hashicorp-vault-the-key-to-secrets-management/)
- **PKI** [high, confirmed]: root CA вне Vault, короткий intermediate, ротация через multiple issuers, `vault pki health-check`. [PKI considerations](https://developer.hashicorp.com/vault/docs/secrets/pki/considerations)
- **Transit (EaaS)** [high/2025-05, confirmed]: крипто без раскрытия ключей, версионированный ciphertext, auto-unseal. [Transit engine](https://developer.hashicorp.com/vault/docs/secrets/transit)
- **GitHub Actions OIDC** [high, confirmed]: keyless через JWT auth; безопасность на `bound_claims` (без них — доступ для любого репо org); пинить vault-action по SHA. [GitHub Actions CI/CD secrets](https://developer.hashicorp.com/well-architected-framework/secure-systems/secure-applications/ci-cd-secrets/github-actions)
- **GitLab CI** [high, confirmed]: `CI_JOB_JWT` удалён в 17.0 → `id_tokens` + `secrets:vault`; биндить к project_id/namespace_id. [GitLab id_token auth](https://docs.gitlab.com/ci/secrets/id_token_authentication/)
- **k8s sync** [high, confirmed]: VSO (наименьшая нагрузка, гибкий auth) / ESO (мульти-провайдер) / Agent Injector (templating). [Vault k8s comparison](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/comparisons), [ESO/k8s secrets 2025](https://infisical.com/blog/kubernetes-secrets-management-2025)
- **SOPS+age > sealed-secrets** [medium/2026-03, confirmed]: читаемые диффы, отдельный ключ на окружение; Flux нативно расшифровывает, ArgoCD нужен KSOPS. [Flux vs ArgoCD secrets](https://oneuptime.com/blog/post/2026-03-13-flux-cd-vs-argocd-secret-management/view)
- **Ротация** [medium/2026-03]: 64% валидных секретов эксплуатируемы спустя 4 года; детекция ≠ ремедиация. [State of Secrets Sprawl 2026](https://thehackernews.com/2026/03/the-state-of-secrets-sprawl-2026-9.html)

### 2.10. Homelab (2026)

- **Стек 2026** [high/2026, confirmed]: Proxmox VE + Talos Linux (immutable K8s) + Flux/ArgoCD + SOPS+age + OpenTofu. [Homelab tour](https://merox.dev/blog/homelab-tour/)
- **onedr0p/cluster-template** [high/2026-05, confirmed]: де-факто старт Talos+Flux+Cilium+cert-manager+spegel+envoy-gateway+external-dns+cloudflared; mise+SOPS+makejinja+Renovate. Требования: 4 ядра/16GB/256GB NVMe/нода. Релиз 2026.5.0. [cluster-template](https://github.com/onedr0p/cluster-template)
- **Мини-ПК** [high/2026, partly — суть confirmed, часть деталей/атрибуций неточна]: Intel N100/N150/N305/N350, idle 5-10W; Quick Sync для Jellyfin; проверять auto power-on + IOMMU; RAM-цены — боль 2026 (32GB sweet spot). Уточнения: N350 не новинка 2026 (Q1'25), max 16GB; dual 2.5GbE есть у EQ14 (не EQ12). [Homelab starter stack 2026](https://www.virtualizationhowto.com/2025/12/ultimate-home-lab-starter-stack-for-2026-key-recommendations/)
- **Топ self-hosted** [high/2026, confirmed]: Immich, Paperless-ngx, Jellyfin (обогнал Plex), *arr+Gluetun, Vaultwarden, Home Assistant, Pi-hole/AdGuard. [2026 homelab stack](https://blog.elest.io/the-2026-homelab-stack-what-self-hosters-are-actually-running-this-year/)
- **Локальный AI** [high/2026]: Ollama сделал локальные LLM тривиальными. [State of homelabs 2026](https://www.archy.net/the-state-of-homelabs-in-2026-smaller-smarter-ai-powered/)
- **MinIO ушёл** [high/2026-04, confirmed]: репо заархивирован 25.04.2026; альтернативы Garage (single-node), versitygw (поверх ZFS), SeaweedFS; RustFS пропустить (alpha+CVE). [Self-hosted S3 after MinIO](https://productimpossible.com/articles/self-hosted-s3-after-minio/)
- **Storage/сеть/бэкапы/мониторинг** [high/2026]: TrueNAS SCALE + ZFS; OPNsense + VLAN + Tailscale; PBS + Restic 3-2-1-1-0; Beszel+Uptime Kuma → Prometheus. [NAS 2026](https://www.technerdo.com/blog/how-to-self-host-nas-2026), [VLAN mistakes 2026](https://www.virtualizationhowto.com/2026/03/5-home-lab-vlan-mistakes-that-will-break-your-network-in-2026/), [Proxmox backup guide](https://nimbus.rdem-systems.com/en/blog/complete-proxmox-backup-guide/), [Server monitoring tools](https://instapods.com/blog/best-server-monitoring-tools/)

### 2.11. CLI/TUI утилиты 2026

- **Ядро modern-Unix** [high/2025-2026, partly]: eza/bat/fd/ripgrep/zoxide/delta/fzf — стандарт; Ubuntu 25.10 тестирует uutils на Rust (но переход НЕ полный — cp/mv/rm в 26.04 остаются GNU). [Rust CLI tools](https://itsfoss.com/rust-alternative-cli-tools/)
- **zoxide+fzf+fzf-tab** [high, confirmed]: наибольший прирост навигации. У пользователя НЕТ zoxide/fzf; atuin уже закрывает Ctrl+R → fzf нужен ради fzf-tab и Ctrl+T/Alt+C. [Modern CLI tools](https://kindatechnical.com/shell-scripting-bash/modern-cli-tools-fzf-ripgrep-bat-fd-eza.html)
- **zsh-плагины** [refuted в части пользователя]: zinit + autosuggestions + fast-syntax-highlighting + zsh-completions + history-substring-search + autopair **УЖЕ настроены** в `tools/zsh/.zshrc` (Turbo mode). Нет только fzf-tab (т.к. нет fzf). [Modern zsh setup](https://wicksipedia.com/blog/modern-zsh-setup/)
- **Реальные пробелы CLI** (после сверки): нет **bat**, **zoxide**, **fzf**, **delta** (delta тоже отсутствует, вопреки исходному предположению); опционально mise/dust/duf/procs/sd.
- **mise** [medium/2026]: polyglot version-manager + task runner + .env. [Terminal Trove new](https://terminaltrove.com/new/)
- **Не менять**: tmux→zellij и zsh→fish/nushell не оправдано при настроенном сетапе [high/2026, confirmed]; yazi/lazygit/k9s/btop/atuin — уже оптимальны. [tmux vs zellij](https://dasroot.net/posts/2026/02/terminal-multiplexers-tmux-vs-zellij-comparison/), [AI CLI tools 2026](https://pasqualepillitteri.it/en/news/586/best-ai-cli-tools-coding-2026)

---

## 3. Что реально доработать в конфиге

Приоритизированная таблица (effort: S<2ч / M полдня / L день+; priority: P0 критично / P1 важно / P2 nice-to-have).

| # | Улучшение | Слой | Priority | Effort | Risk | Источник/обоснование |
|---|-----------|------|----------|--------|------|----------------------|
| 1 | Зашифровать `.env`/`private/` через SOPS+age (plaintext JIRA/GitLab/Nomad/OpenSearch токены) | dotfiles | **P0** | M | medium | нарушение security.md; SOPS+age — стандарт 2026 |
| 2 | PreToolUse-хук на Bash: блок деструктивных команд + детект секретов | Claude | **P0** | M | medium | enforcement поверх deny-листов; `permissionDecision` confirmed |
| 3 | PostToolUse-хук авто-линтинга (terraform fmt/validate, ruff, ansible-lint, kubeconform) | Claude | P1 | M | low | переносит path-scoped rules в авто-запуск; `async:true` |
| 4 | CI-тест install.sh (matrix ubuntu+macos, двойной прогон на идемпотентность) | dotfiles | P1 | M | low | bootstrap не тестируется; вскроет FIXME ~/dotfiles |
| 5 | Идемпотентный create_symlinks, убрать `sudo rm -rf`/`sudo ln` | dotfiles | P1 | S | medium | опасный destructive-пересоздание по target из массива |
| 6 | SessionStart-хук + CLAUDE_ENV_FILE для OpenSearch-кредов (cw-analyze-logs) | Claude | P1 | M | low | закрывает пробел + убирает plaintext; CLAUDE_ENV_FILE confirmed |
| 7 | Добавить bat, zoxide, fzf, delta в nix-пакеты + интеграция в zsh (fzf-tab) | dotfiles | P1 | S | low | реальные CLI-пробелы (delta тоже отсутствует) |
| 8 | Встроить Claude в devcontainer (official feature + named volume + containerEnv) | dotfiles | P1 | M | low | воспроизводимость, пин install-скрипта |
| 9 | Stop-хуки в frontmatter devops-агентов (→ SubagentStop) для профильной валидации | Claude | P2 | M | low | tf/k8s/ansible/nomad validate по завершении агента |
| 10 | Обёртка `claude-remote` без telemetry-флагов (для Routines/Remote Control) | Claude | P2 | S | low | DISABLE_TELEMETRY гейтит /schedule + eligibility |
| 11 | `isolation: worktree` для devops-агентов + `.claude/worktrees/` в gitignore | Claude | P2 | S | low | параллельный devops-review без затирания файлов |
| 12 | Убрать дубль атрибуции: `includeCoAuthoredBy` + `CLAUDE_CODE_DISABLE_ATTRIBUTION` → `attribution`-объект | Claude | P2 | S | low | deprecated, риск рассинхрона |
| 13 | Добавить `$schema` в settings.json | Claude | P2 | S | low | автокомплит 80+ опций |
| 14 | Исправить FIXME ~/dotfiles vs ~/.dotfiles (path-независимость через DOTFILES_ROOT) | dotfiles | P2 | S | low | задокументированный баг в Linux install |
| 15 | Глобально `DevPod DOTFILES_URL` (HTTPS) вместо дублирования bootstrap | dotfiles | P2 | S | low | DevPod автодетектит install.sh |
| 16 | Statusline: адаптация под COLUMNS/LINES + индикатор output_style | Claude | P2 | S | low | ломается на узком терминале (Tailscale) |
| 17 | Tailscale + tmux auto-attach + caffeinate (контроль Mac с телефона) | dotfiles | P2 | M | low | Tailscale уже используется (TIMING_MCP CGNAT-адрес) |
| 18 | mise для версий языков/тулов | dotfiles | P2 | M | low | разъезд nix-каналов macOS/Linux |
| 19 | Обновить ссылки docs.anthropic.com → code.claude.com/docs в knowledge | Claude | P2 | S | low | домен переехал |
| 20 | launchd-агент `claude -p` для durable расписаний с локальным доступом | Claude | P3 | M | medium | Routines отключены флагами; /loop только при открытой сессии |
| 21 | Linux home-manager standalone в flake (вместо imperative nix-env) | dotfiles | P3 | L | medium | flake-linux.nix не подключён к outputs; постепенная миграция |

> Примечание по достоверности таблицы: пп. 7 скорректирован — zinit/autosuggestions/highlighting у пользователя **уже стоят** (исходное предположение опровергнуто сверкой репо), а `delta` **отсутствует** и добавлен в список. П. 6/1 связаны: SessionStart-хук должен брать из SOPS-зашифрованного файла.

---

## 4. Quick wins (top-10, по приоритету)

1. **[P0]** Зашифровать `.env`/`private/` через SOPS+age, age-ключ вне репо (закрывает прямое нарушение security.md). `age`+`sops` в `common-packages.nix`.
2. **[P0]** PreToolUse-хук `hooks/pretooluse-guard.sh` (matcher Bash) — детерминированный блок destructive-команд + секрет-паттернов на уровне исполнения.
3. **[P1]** PostToolUse-хук `hooks/posttooluse-lint.sh` (matcher Edit|Write, `async:true`) — terraform fmt/validate, ruff, ansible-lint, kubeconform по расширению файла.
4. **[P1]** CI `.github/workflows/test-install.yml` — matrix [ubuntu-контейнер→linux/install.sh, macos→smoke симлинков], двойной прогон на идемпотентность.
5. **[P1]** Переписать `create_symlinks` в `platform/common.sh`: убрать sudo, guard (skip если уже корректный симлинк), backup `*.before-dotfiles`, `ln -sfn`.
6. **[P1]** Добавить `bat zoxide fzf delta` в nix-пакеты + `eval "$(zoxide init zsh)"`, fzf-tab через zinit, `MANPAGER` через bat.
7. **[P1]** SessionStart-хук `hooks/sessionstart-secrets.sh` → `sops -d` → `export OPENSEARCH_*` в `$CLAUDE_ENV_FILE`; обновить `cw-analyze-logs/SKILL.md`.
8. **[P2]** `$schema` в settings.json + замена дублирующей атрибуции на `attribution`-объект; проверить отсутствие вызовов удалённого `/output-style`.
9. **[P2]** Обёртка `claude-remote` в `tools/zsh`: `env -u DISABLE_TELEMETRY -u CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC claude --rc`; диагностика `claude doctor`.
10. **[P2]** Stop-хуки в frontmatter tf/k8s/ansible/nomad-агентов (→ SubagentStop) + `isolation: worktree` + `.claude/worktrees/` в gitignore.

---

## 5. Источники

### Claude Code (code.claude.com/docs — источник истины)
- https://code.claude.com/docs/en/remote-control
- https://code.claude.com/docs/en/claude-code-on-the-web
- https://code.claude.com/docs/en/routines
- https://code.claude.com/docs/en/desktop
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/skills
- https://code.claude.com/docs/en/scheduled-tasks
- https://code.claude.com/docs/en/worktrees
- https://code.claude.com/docs/en/goal
- https://code.claude.com/docs/en/output-styles
- https://code.claude.com/docs/en/statusline
- https://code.claude.com/docs/en/channels
- https://code.claude.com/docs/en/devcontainer
- https://claude.com/blog/introducing-dynamic-workflows-in-claude-code
- https://www.anthropic.com/product/claude-cowork
- https://claude.com/product/cowork
- https://blog.vincentqiao.com/en/posts/claude-code-settings-misc/
- https://www.mindstudio.ai/blog/claude-code-headless-mode-autonomous-agents

### Управление Mac с телефона
- https://samwize.com/2026/02/08/control-your-mac-from-your-iphone-safely-tailscale-ssh-tmux/
- https://zenn.dev/shimo4228/articles/termius-iphone-claude-code?locale=en
- https://onepilotapp.com/blog/best-mobile-ssh-app-2026
- https://github.com/siteboon/claudecodeui

### dotfiles / Nix / DevPod
- https://www.chezmoi.io/comparison-table/
- https://gbergatto.github.io/posts/tools-managing-dotfiles/
- https://dotfiles.io/en/guides/secret-management/
- https://discourse.nixos.org/t/handling-secrets-in-nixos-an-overview-git-crypt-agenix-sops-nix-and-when-to-use-them/35462
- https://tomforb.es/blog/testing-my-dotfiles/
- https://nix-community.github.io/home-manager/
- https://gvolpe.com/blog/home-manager-dotfiles-management/
- https://news.ycombinator.com/item?id=45421485
- https://github.com/AlexNabokikh/nix-config
- https://determinate.systems/blog/nix-support-for-macos-sequoia/
- https://devenv.sh/guides/using-with-flake-parts/
- https://blog.cachix.org/posts/2026-01-28-cachix-deploy-ga-and-cachix-1-10/
- https://github.com/loft-sh/devpod
- https://github.com/loft-sh/devpod/releases
- https://devpod.sh/docs/developing-in-workspaces/prebuild-a-workspace
- https://devpod.sh/docs/developing-in-workspaces/dotfiles-in-a-workspace
- https://www.bunnyshell.com/comparisons/github-codespaces-alternative/
- https://nixos-and-flakes.thiscute.world/development/dev-environments

### DevOps / Kubernetes
- https://jorijn.com/en/blog/opentofu-vs-terraform-2026-the-fork-finally-diverged/
- https://opentofu.org/blog/opentofu-1-7-0/
- https://roadie.io/blog/platform-engineering-in-2026-why-diy-is-dead/
- https://dev.to/x4nent/crossplane-v22-deep-dive-pipeline-inspector-cel-validation-and-production-control-planes-1ed9
- https://cloudnativenow.com/kubecon-cloudnativecon-europe-2026/cncf-announces-kyverno-graduation-as-policy-as-code-adoption-grows/
- https://dev.to/x4nent/opentelemetry-ebpf-instrumentation-obi-the-complete-guide-kubecon-eu-2026-beta-launch-5e2o
- https://aquilax.ai/blog/supply-chain-artifact-signing-slsa
- https://www.infoq.com/news/2026/04/aws-devops-agent-ga/
- https://platformengineering.org/blog/terraform-vs-pulumi-vs-crossplane-iac-tool
- https://kubernetes.io/releases/
- https://kubernetes.io/blog/2025/08/27/kubernetes-v1-34-release/
- https://www.okteto.com/blog/ingress-nginx-controller-deprecation-your-migration-guide-to-kubernetes-gateway-api/
- https://www.infoq.com/news/2026/02/cilium-119/
- https://kyverno.io/docs/guides/pod-security/
- https://kubernetesguru.com/ai-ml-on-kubernetes-2026-stack-guide/
- https://leanopstech.com/blog/kubernetes-rightsizing-vpa-hpa-krr-karpenter-2026/
- https://www.virtualizationhowto.com/2025/03/best-kubernetes-distributions-for-home-lab-enthusiasts-in-2025/

### Vault / секреты
- https://digitalis.io/post/choosing-a-secrets-storage-hashicorp-vault-vs-openbao
- https://sjramblings.io/hashicorp-vault-the-key-to-secrets-management/
- https://developer.hashicorp.com/vault/docs/secrets/pki/considerations
- https://developer.hashicorp.com/vault/docs/secrets/transit
- https://developer.hashicorp.com/well-architected-framework/secure-systems/secure-applications/ci-cd-secrets/github-actions
- https://docs.gitlab.com/ci/secrets/id_token_authentication/
- https://developer.hashicorp.com/vault/docs/deploy/kubernetes/comparisons
- https://infisical.com/blog/kubernetes-secrets-management-2025
- https://oneuptime.com/blog/post/2026-03-13-flux-cd-vs-argocd-secret-management/view
- https://thehackernews.com/2026/03/the-state-of-secrets-sprawl-2026-9.html

### Homelab
- https://merox.dev/blog/homelab-tour/
- https://github.com/onedr0p/cluster-template
- https://www.virtualizationhowto.com/2025/12/ultimate-home-lab-starter-stack-for-2026-key-recommendations/
- https://blog.elest.io/the-2026-homelab-stack-what-self-hosters-are-actually-running-this-year/
- https://www.archy.net/the-state-of-homelabs-in-2026-smaller-smarter-ai-powered/
- https://productimpossible.com/articles/self-hosted-s3-after-minio/
- https://www.technerdo.com/blog/how-to-self-host-nas-2026
- https://www.virtualizationhowto.com/2026/03/5-home-lab-vlan-mistakes-that-will-break-your-network-in-2026/
- https://nimbus.rdem-systems.com/en/blog/complete-proxmox-backup-guide/
- https://instapods.com/blog/best-server-monitoring-tools/

### CLI/TUI
- https://itsfoss.com/rust-alternative-cli-tools/
- https://kindatechnical.com/shell-scripting-bash/modern-cli-tools-fzf-ripgrep-bat-fd-eza.html
- https://wicksipedia.com/blog/modern-zsh-setup/
- https://dasroot.net/posts/2026/02/terminal-multiplexers-tmux-vs-zellij-comparison/
- https://www.x-cmd.com/install/25-ls/
- https://www.heyuan110.com/posts/ai/2026-04-10-lazygit-guide/
- https://www.x-cmd.com/install/kdash/
- https://pasqualepillitteri.it/en/news/586/best-ai-cli-tools-coding-2026
- https://terminaltrove.com/new/
- https://www.eagleflow.fi/posts/2025-08-25/replacing-cli-tools-with-modern-alternatives
- https://computingforgeeks.com/best-linux-macos-shells/

### Опущено как непроверяемое/опровергнутое
- «Routines launched April 14, 2026» — точная дата unverifiable из primary doc (косвенно подтверждается beta-заголовком).
- «>64% enterprise GitOps as primary delivery (CNCF)» — **refuted** как CNCF-факт.
- ingress-nginx retired «31 марта 2026» — точная дата unverifiable («best-effort до марта 2026»).
- `continueOnBlock` для PostToolUse — официально не подтверждён (только сторонние гайды).
- Атрибуция деталей мини-ПК (N100/EQ12 dual 2.5GbE и т.п.) к virtualizationhowto-статье — частично **refuted** (статья про Ryzen), детали верны по сути из других источников.
