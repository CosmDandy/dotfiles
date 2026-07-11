# Аудит dotfiles-стека

Аудит охватывает 13 инструментов личного dotfiles-стека (macOS, nix-darwin на M1 + Linux DevPod/DevContainers): aerospace, atuin, btop, ghostty, git, k9s, lazygit, leader-key, lnav, orbstack, starship, tmux, zsh. Методика — двухступенчатая: по каждому инструменту Sonnet-агент проводил исследование (конфиги в репо, живая система, официальные release notes и документация через web), затем Opus-агент выносил финальный вердикт, перепроверяя claims исследователя против первоисточников (GitHub releases, официальные docs) и локальной системы. Все версии и находки ниже прослеживаются до этих карточек; непроверенные утверждения помечены явно.

## Сводка

| Инструмент | Роль | Версия (стоит / актуальная) | Вердикт | Нужен? | Приоритет |
|---|---|---|---|---|---|
| atuin | Shell history + sync + AI | 18.16.1 / 18.17.0 | tweak | да | **high** (AI capabilities не ограничены) |
| git | VCS: signing, hooks, includeIf | 2.54.0 / 2.55.0 | tweak | да | **high** (gitleaks hook молча отключается) |
| lnav | Log viewer TUI | не установлен на macOS / v0.14.0 | keep | да | **high** (dangling config на macOS) |
| zsh | Interactive shell + zinit | 5.9.1 / **5.10** | tweak | да | **medium** (5.10 — security release) |
| btop | Resource monitor TUI | 1.4.7 / 1.4.7 | tweak | да | medium (config drift из-за save_config_on_exit) |
| ghostty | Terminal emulator | 1.3.1 / 1.3.1 | tweak | да | medium (notify-action не срабатывает) |
| k9s | Kubernetes TUI | неизвестно / 0.51.0 | keep | да | medium (проверить версию на живых хостах) |
| lazygit | Git TUI | 0.62.2 / 0.63.0 | keep | да | low |
| tmux | Terminal multiplexer | 3.7b / 3.7b | keep | да | low |
| starship | Shell prompt | 1.26.0 / 1.26.0 | keep | да | low |
| orbstack | Container/VM runtime | 2.2.1 / 2.2.1 | keep | да | low |
| leader-key | Hotkey launcher | 1.17.3 / 1.17.3 | keep | да | low |
| aerospace | Tiling WM | 0.21.2-Beta / 0.21.2-Beta | keep | да | low |

## Обновить сейчас

- **zsh: 5.9.1 → 5.10** — единственное обновление с security-мотивацией. Исследователь ошибочно посчитал 5.9.1 актуальной; decision-агент перепроверил: 5.10 — «security and feature release», upstream рекомендует «all zsh installations encouraged to upgrade as soon as possible». Механизм: `nix flake update` в `platform/nix` + `darwin-rebuild switch` (сначала убедиться, что nixpkgs дошёл до 5.10).
- **atuin: 18.16.1 → 18.17.0** — 1 minor позади (релиз 2026-07-09, за 2 дня до аудита). Обновлять через bump nixpkgs/flake, **не** через `atuin update` — установлен декларативно через nix-darwin.
- **git: 2.54.0 → 2.55.0** — 1 minor позади (tag v2.55.0 от 2026-06-29). Рутинное обновление через package manager, без security-фиксов.
- **lazygit: 0.62.2 → 0.63.0** — 1 minor позади; 0.63.0 добавляет direnv support и polling внешних изменений. Через обычный `nix flake update`, миграция конфига не нужна.
- **k9s: версия неизвестна** — бинарь отсутствовал в audit-окружении; актуальная 0.51.0. Выполнить `k9s version` на реальных хостах и при необходимости поднять pin.

Актуальны и обновления не требуют: aerospace, btop, ghostty, orbstack, starship, tmux, leader-key.

## Кандидаты на выброс / замену

**Нет.** Ни один инструмент не получил вердикт drop или replace — все 13 подтверждённо используются (симлинки, install-скрипты, нетривиальные конфиги) и остаются в стеке. Единственные примечания «на горизонт»:

- **leader-key** — upstream-автор сместил фокус на коммерческий launcher Tuna (Leader Key остаётся free/open-source, deprecation не объявлен); ожидать замедления обновлений, действий сейчас не требуется.
- **lnav** — если инструмент осознанно Linux-only, на macOS стоит убрать симлинк конфига вместо установки бинаря (см. детали ниже).

## Кросс-стек консистентность

**Цветовая тема.** Ядро стека последовательно держится Solarized: ghostty (iTerm2 Solarized Light/Dark с авто-переключением light/dark), k9s (два рукописных solarized-скина + OSC 11-детект фона терминала в `k9s.zsh`), zsh (zsh-autosuggestions в цвете `#586e75` «solarized base01»), tmux-thumbs (`#cb4b16` / `#268bd2` — Solarized orange/blue), nvim (solarized-osaka по данным карточки k9s). **Выбиваются:** lnav — тема **monokai** (единственный не-Solarized инструмент с явной темой, и без light-варианта, тогда как ghostty/k9s переключаются автоматически); btop — builtin «Default» без версионируемого кастомного `.theme`; lazygit — вообще без `gui.theme`; starship — цвета захардкожены per-module без централизованной `palette`. Дополнительная мелочь: в ghostty `cursor-color=2aa198` захардкожен и не следует за переключением темы.

**Шрифты.** Ghostty задаёт JetBrainsMono Nerd Font 15pt; starship активно использует Nerd Font-глифы; tmux/btop/lnav наследуют шрифт терминала. **Несоответствие:** lazygit не включает `gui.nerdFontsVersion` — иконки остаются ASCII, хотя Nerd Font гарантированно есть.

**Клавиши.** Сильная и редкая консистентность: кастомная направленная раскладка **y/h/a/e** (вместо hjkl) едина для aerospace (focus/move/swap) и tmux (select-pane с Neovim-passthrough) — это осознанная сквозная схема. Vi-mode выдержан в zsh (`set -o vi`) и tmux (`mode-keys vi`, `status-keys vi`). **Несоответствия:** btop с `vim_keys=false` (только стрелки) — выбивается из vi-центричного стека; atuin на emacs-подобных дефолтах с leader-prefix `h`; lnav на дефолтном keymap. Модификаторы разнесены без коллизий: aerospace — alt, tmux — prefix C-s, leader-key — F10, k9s — Shift-1..0 hotkeys + Ctrl-* plugins.

**Итого:** самые дешёвые выравнивания — solarized-тема для lnav и btop, `nerdFontsVersion` в lazygit, решение по `vim_keys` в btop, `palette` в starship.

## Детально по инструментам

### aerospace

**Назначение:** i3-подобный tiling WM для macOS (Accessibility API, без отключения SIP). **Версия:** 0.21.2-Beta установлена = 0.21.2-Beta последняя (проект в public beta, стабильного 1.0 не существует). Версия определена по пути Caskroom, а не по `aerospace --version` (бинарь вне PATH в audit-shell) — подтверждена по releases page. **Вердикт: keep** — глубоко интегрирован (симлинк, brew tap через darwin-configuration.nix, setup-symlinks.sh), конфиг ~15KB: accordion default layout, y/h/a/e-раскладка, ~40 правил on-window-detected по bundle id, разнос workspaces 0–4/5–9 по двум мониторам.

Пробелы: `auto-reload-config` оставлен false при активно редактируемом конфиге; нет `exec-on-workspace-change` (status bar); `after-login/startup-command` пустые (подтвердить намеренность). Неиспользуемое: focus-follows-mouse, цикл только по непустым workspaces, `[exec.env-vars]`. Security: чисто.

**Флаги проверки:** claim исследователя о «soft deprecated `if.app-id`» **опровергнут** decision-агентом — это официальный документированный синтаксис, мигрировать не нужно. Расхождение даты релиза (2026-07-07 vs «July 7, 2025» в fetch) — артефакт парсинга, не влияет на вывод.

Действия: 1) `auto-reload-config = true` (low/low); 2) подтвердить пустые startup-команды / опционально status bar через exec-on-workspace-change (low/medium).

### atuin

**Назначение:** shell history с fuzzy-поиском, E2E-sync на self-hosted сервер (`https://atuin.cosmdandy.ru`), опциональный AI-ассистент. **Версия:** 18.16.1 / 18.17.0 — 1 minor позади. **Вердикт: tweak.** Конфиг чистый и осознанный (~24 non-default настроек: fuzzy search, filter_mode=host, prefix `h`, sync.records=true), без мёртвых ключей, но два реальных пробела в гигиене.

Ключевые пробелы: **(1)** `ai.enabled=true` без блока `[ai.capabilities]` — command_execution, file_tools, history_search/output наследуют разрешающие upstream-дефолты на машине с Terraform/Ansible/K8s/Nomad-секретами в истории; **(2)** `secrets_filter` не закреплён явно (полагается на дефолт бинаря), нет `history_filter`/`cwd_filter` как defense-in-depth. Неиспользуемое: daemon mode (sync вне hot path), workspaces/filter_mode=workspace, темы.

**Флаги проверки:** совет исследователя «`atuin update`» скорректирован — установка декларативная (darwin-configuration.nix), обновлять через nixpkgs bump. Дата «2026-05-12» из WebSearch-сниппета ошибочна, авторитетный источник даёт 2026-07-09 — сама версия подтверждена.

Действия: 1) явно ограничить `[ai.capabilities]` или выключить ai (**high**/low); 2) закрепить `secrets_filter=true` + добавить history_filter/cwd_filter (medium/low); 3) bump до 18.17.0 через nix, когда появится в nixpkgs (low/low); 4) пересмотреть транзитный флаг `sync.records=true` при будущих апгрейдах (low/low).

### btop

**Назначение:** TUI-монитор ресурсов (CPU/mem/net/proc/GPU). **Версия:** 1.4.7 = 1.4.7, актуален; заголовок конфига сгенерирован тем же 1.4.7 — ничего не устарело. **Вердикт: tweak** — из-за одного footgun: `save_config_on_exit=true` заставляет btop перезаписывать симлинкнутый tracked-конфиг при каждом выходе → тихий drift версионируемого файла.

Пробелы: GPU-поддержка скомпилирована и сконфигурирована (shown_gpus, gpu_mirror_graph), но в `shown_boxes = "cpu mem net proc"` нет gpu-бокса — фичи dormant; `update_ms=500` ниже рекомендованных 2000ms (осознанный trade-off?); тема — builtin Default, кастомный `.theme` не версионируется; `vim_keys=false` при vi-центричном стеке. Security: чисто.

Действия: 1) `save_config_on_exit = false` (medium/low); 2) добавить gpu0 в shown_boxes (low/low); 3) решить по vim_keys (low/low).

### ghostty

**Назначение:** основной терминал на macOS; keyboard-first, интеграция с zsh/tmux/starship tab-title workflow. **Версия:** 1.3.1 = 1.3.1, актуален. **Вердикт: tweak.** Конфиг 28 строк, продуманный (mouse-фичи выключены под TUI-приложения, shell-integration-features=no-title под кастомный tab-title.zsh, shift+enter=ESC+CR для REPL/Claude Code), без deprecated-ключей.

Ключевой пробел: `desktop-notifications=true` + `notify-on-command-finish=unfocused` + порог 10s настроены, но `notify-on-command-finish-action` остаётся дефолтным **bell only** — реальное macOS-уведомление о завершении долгих команд, судя по всему, никогда не приходит, хотя это очевидный intent конфига. Security: `clipboard-paste-protection=false` — осознанное отключение защиты от paste-атак, docs рекомендуют держать включённой (см. Security). Неиспользуемое: `window-save-state=always` (логично при `fullscreen=true`), quick terminal, clipboard-trim-trailing-spaces.

Действия: 1) добавить `notify-on-command-finish-action = no-bell,notify` (medium/low); 2) подтвердить намеренность `clipboard-paste-protection=false` или убрать строку (low/low); 3) опционально `window-save-state = always` (low/low).

### git

**Назначение:** VCS-ядро стека: SSH-signing (inline `key::`), includeIf work-профиль, repo-tracked hooks. **Версия:** 2.54.0 / 2.55.0 — 1 minor позади. **Вердикт: tweak.** Конфиг сильно выше среднего: fsckObjects на transfer/fetch/receive, rerere, histogram diff, pull.rebase, push.autoSetupRemote, pre-commit gitleaks + pre-push защита main/master.

Ключевой дефект: **pre-commit hook мягко деградирует** — при отсутствии gitleaks (`command -v gitleaks`) молча выходит с 0, и secret-сканирование исчезает без какого-либо предупреждения, что противоречит собственному security.md пользователя. Пробелы-nice-to-have: нет `merge.conflictstyle=zdiff3`, `diff.colorMoved`, `help.autocorrect`, ни одного alias, нет пейджера (delta), `branch.sort`, `git maintenance`.

**Флаги проверки:** заявленная исследователем «2.55.0.2 (2026-06-29/07-03)» — **сфабрикованный patch-label**: верифицирован только тег v2.55.0 от 2026-06-29. Суть («1 minor позади») верна.

Действия: 1) hardening pre-commit — видимый warning в stderr (или non-zero exit) при отсутствии gitleaks (**high**/low); 2) добавить zdiff3 + colorMoved + autocorrect=prompt (medium/low); 3) минимальный `[alias]` блок (low/low); 4) bump до 2.55.0 (low/low); 5) опционально branch.sort / git maintenance (low/low).

### k9s

**Назначение:** Kubernetes TUI — центральный элемент k8s-workflow (плагины stern/trivy/dive/kubectl-neat/argocd). **Версия: установленная неизвестна** — бинарь отсутствует в audit-sandbox (k9s — zsh-обёртка над `command k9s`); последняя стабильная 0.51.0. На реальных машинах ставится через Nix (Linux). **Вердикт: keep** — многофайловый качественный конфиг (aliases/hotkeys/plugins/views + 2 рукописных solarized-скина с OSC-переключателем), безопасный: единственный мутирующий plugin argocd-sync с `confirm:true`, hotkeys без коллизий, секретов нет.

Пробелы/неиспользуемое: `imageScans.enable=false` при уже установленном trivy; views `:xray`/`:pulses` нигде не surfaced (скин даже определяет xray-цвета); закомментированный Flux-блок в plugins.yaml — мёртвый, но с rationale (стек на ArgoCD); per-context overrides (readOnly для prod-контекстов) не используются.

Действия: 1) `k9s version` на каждом реальном хосте vs 0.51.0, bump pin при отставании (medium/low); 2) `imageScans.enable: true` (low/low); 3) hotkeys на :xray/:pulses (low/low).

### lazygit

**Назначение:** интерактивный git-клиент (`alias lg`). **Версия:** 0.62.2 / 0.63.0 — 1 minor позади. **Вердикт: keep.** Конфиг 23 строки, намеренно минимальный: все confirmation-попапы отключены (осознанный low-friction), `overrideGpg: True`, mainBranches под конвенции организации, editPreset nvim. Deprecated-ключей нет, секретов нет.

Пробелы (всё опционально): нет diff-пейджера (delta), нет `gui.nerdFontsVersion` (иконки ASCII при включённом showFileTree и Nerd Font в терминале), нет `gui.theme` — визуально беднее остального стека; customCommands не используются.

Действия: 1) bump до 0.63.0 при следующем `nix flake update` (low/low); 2) опционально delta под git.paging (low/low); 3) опционально `nerdFontsVersion: "3"` (low/low); 4) косметика: `True` → `true` (low/low).

### leader-key

**Назначение:** hotkey-launcher (Leader Key.app by mikker) — вложенные leader-последовательности для запуска приложений, raycast://-deep-links, profile-скриптов. **Версия:** 1.17.3 = 1.17.3 (верифицировано через GitHub API), auto_updates включён. **Вердикт: keep** — 565-строчный config.json с 14 доменными группами + 4 profile-скрипта, секретов нет.

**Флаги проверки:** claim исследователя, что theme/shortcut/cheatsheet «живут только в UserDefaults и не определимы из репо», — **ложный**: `platform/macos/install-extra.sh:39` (`setup_app "Leader Key"`) документирует их (Shortcut F10, Theme Breadcrumbs, Activation «Reset group selection» и т.д.); намёк на «mysteryBox/⌃ по умолчанию» также неверен для этого репо. Находка про несовпадение путей (`/System/Volumes/Data/Applications/...` vs `/Applications/...` в profile-скриптах) реальна, но **чисто косметическая** — macOS firmlinks резолвят оба пути в один файл. Контекст: upstream-автор сместил фокус на платный Tuna; deprecation нет.

Действия: 1) нормализовать пути в enable-work-profile.sh (low/low); 2) добавить `open leaderkey://config-reload` в setup-symlinks.sh после симлинка (low/low); 3) заметка-указатель в tools/leader-key/ на setup_app-блок как source of truth для UserDefaults (low/low).

### lnav

**Назначение:** TUI log viewer с merge/SQL-запросами по логам. **Версия: не установлен на этой (macOS) машине** — бинарь отсутствует и **никогда не объявлялся для macOS** (нет ни в install-brew.sh, ни в nix), ставится только через Linux-профиль; последняя стабильная v0.14.0 (2026-04-12, подтверждено через GitHub API). **Вердикт: keep**, но с главной конкретной проблемой — **dangling config на macOS**: `setup-symlinks.sh` создаёт симлинк `~/.lnav/configs/default/config.json`, которым нечему пользоваться.

Конфиг 28 строк, чистый: theme monokai, movement/mode=cursor, tuning (min-free-space 32MB, cache-ttl 2d, кастомный scp transfer-command) — без rationale-комментариев. Deprecated-ключей нет. Неиспользуемое — по сути весь value proposition: ни одного кастомного log format (`~/.lnav/formats` не существует) при DevOps-тяжёлом стеке, ни SQL search-tables, ни watch expressions.

Действия: 1) починить install parity — либо добавить lnav в macOS-установку, либо убрать macOS-симлинк, если инструмент намеренно Linux-only (**high**/low); 2) определить хотя бы один кастомный log format для частого DevOps-источника (medium/medium); 3) прокомментировать или откатить tuning-значения (low/low).

### orbstack

**Назначение:** замена Docker Desktop на macOS (Docker engine + Linux VMs). **Версия:** 2.2.1 (build 2020100) = 2.2.1 актуальная (release notes, июнь 2026). **Вердикт: keep.** `tools/orbstack/apply.sh` — образцовый идемпотентный config-as-code (пишет только при drift, машинно-специфичные ключи осознанно не пинит); все 8 управляемых ключей подтверждены живым `orb config show` (cpu=7, memory_mib=6144, rosetta, k8s.enable=false и др.). Секретов нет.

Пробелы: `docker.expose_ports_to_lan=true` не задокументирован как security-исключение (собственный security.md требует justification; плюс дефолтный `machines.expose_ports_to_lan=true` тоже открывает порты Linux-машин в LAN); единицы `cpu=7` (абсолютные ядра, не проценты) не прокомментированы. Неиспользуемое: cloud-init для воспроизводимых VM, k8s.enable (осознанно off).

Действия: 1) justification-комментарий над expose_ports_to_lan (low/low); 2) комментарий про единицы cpu/memory (low/low).

### starship

**Назначение:** cross-shell prompt (zsh), DevOps-курированный: k8s, terraform, aws/gcloud/azure, docker_context, direnv, sudo, custom `vm`-модуль. **Версия:** 1.26.0 = 1.26.0 (верифицировано локально и по release tag). **Вердикт: keep.** 116-строчный осознанный конфиг, deprecated-ключей и секретов нет.

Пробелы: `git_status.format = ''` полностью прячет dirty/ahead-behind индикаторы (самый поведенчески значимый выбор — подтвердить намеренность); нет root `format` (implicit `$all`), нет `palette` (стили захардкожены per-module), нет тюнинга `command_timeout` при том, что prompt работает и в DevPod-контейнерах.

**Флаги проверки:** claim «custom.vm — dead weight на macOS» decision-агент счёл преувеличением: конфиг деплоится и в Linux-devcontainers, где модуль живой; на macOS when-check тихо no-op'ится. Сниппет WebSearch с «1.24.2 latest» отброшен — тег v1.26.0 авторитетен.

Действия: 1) подтвердить намеренность `git_status.format=''` или вернуть компактный dirty-глиф (low/low); 2) `command_timeout` для remote-окружений (low/low).

### tmux

**Назначение:** слой сессий/панелей под Neovim+Ghostty; интеграция с Claude Code (bell-уведомления, pane-title c детектом процессов). **Версия:** 3.7b = 3.7b (bugfix-релиз 2026-07-01), актуален. **Вердикт: keep** — один из самых инженерно проработанных конфигов стека: prefix C-s, y/h/a/e c Neovim-passthrough, документированные inline хаки под SSH/DevPod-баги (sync frames, cud1-фикс со ссылкой на loft-sh/devpod#932), tmux-thumbs через Nix вместо TPM (без cargo-сборки), динамическое session-menu. Секретов нет.

Пробелы: truecolor задан устаревшим `terminal-overrides ":Tc"` вместо рекомендованного с 3.2+ `terminal-features ":RGB"` — внутренняя непоследовательность, т.к. terminal-features уже используется рядом для sync-хака; нет session-persistence (resurrect/continuum) при history-limit 1,000,000 и сессионном workflow — reboot теряет всё; confirm только на kill-session, не на kill-pane/window.

Действия: 1) мигрировать Tc → `terminal-features ",*:RGB"` (low/low); 2) опционально tmux-resurrect + continuum (low/medium); 3) опционально scratch popup / floating panes 3.7 (low/low).

### zsh

**Назначение:** interactive shell на обеих платформах; хаб стека (zinit, self-healing completions, conf.d-модули k9s/kube/tab-title). **Версия: 5.9.1 / 5.10 — отстаёт, и это security-релиз.** **Вердикт: tweak.**

**Флаги проверки:** это единственная карточка с `version_claim_ok: false` — исследователь заявил «5.9.1 = latest, current», decision-агент опроверг: актуальная — **5.10**, upstream называет её «security and feature release» с рекомендацией обновляться как можно скорее. Сама строка «5.9.1» нетипична для mainline (вероятно Nix/vendor patch-suffix), но в любом случае позади 5.10. Также помечено: `$HOME/.dotfiles/.env` (сорсится через `set -a`) и `private/zsh/*.sh` не читались — секретная поверхность shell не полностью аудирована (сам паттерн — секреты вне tracked-репо — корректен).

Конфиг выше среднего: adaptive compinit (24h), self-healing генерация completions для kubectl/helm/talosctl/k9s/devpod/docker/gh/glab/atuin, OSC11-детект темы, SSH_AUTH_SOCK-фикс под tmux, turbo-mode zinit. Пробелы: нет `HIST_EXPIRE_DUPS_FIRST` при 7 других HIST_*-опциях; нет zoxide/AUTO_PUSHD при куче ручных cd-алиасов; ручной compinit-танец дублирует zinit-овый `zpcompinit`. Security-заметки — см. ниже.

Действия: 1) обновить zsh до 5.10 через nixpkgs bump + darwin-rebuild switch (**medium**/low — security-релиз, но конкретный критичный CVE не назван); 2) HIST_EXPIRE_DUPS_FIRST (low/low); 3) опционально zoxide или AUTO_PUSHD (low/low).

## Security

Хардкоженных секретов, токенов и credentials **не найдено ни в одном из 13 инструментов**. Консолидированные security-релевантные находки (позиционные риски, не утечки):

1. **atuin — AI с полными capabilities (наиболее приоритетно).** `ai.enabled=true` без `[ai.capabilities]` — command_execution, file_tools, history_search/output разрешены по upstream-дефолтам на машине, чья shell-history содержит infra-команды (Terraform/Ansible/K8s/Nomad). Плюс `secrets_filter` не закреплён явно (дефолт безопасен, но неверифицируем из tracked-файла), нет history_filter/cwd_filter. Sync идёт на self-hosted `https://atuin.cosmdandy.ru` — под контролем пользователя, E2E-ключ (key_path) корректно не в репо; убедиться в его бэкапе.
2. **git — секрет-сканирование молча деградирует.** pre-commit gitleaks через `command -v gitleaks` тихо exit 0 при отсутствии бинаря — на машине без gitleaks защита исчезает незаметно, вопреки требованию security.md о secret detection. Ключи в .gitconfig/.allowed_signers/known_hosts — только публичный материал, чисто.
3. **ghostty — `clipboard-paste-protection = false`** отключает защиту от paste-атак (скрытые newlines/control chars в буфере), docs рекомендуют держать включённой; 1.3.0 специально усиливал обработку вставляемых control-символов. Подтвердить намеренность или убрать строку.
4. **zsh — три позиционных пункта:** (a) алиасы `cl`/`cly` запускают claude с `--permission-mode bypassPermissions` / `--dangerously-skip-permissions` — осознанная, но постоянная full-auto-позиция, вшитая в shell; (b) SSH_AUTH_SOCK симлинкается на фиксированный предсказуемый путь `~/.ssh/ssh_auth_sock` — приемлемо для single-user машины, недопустимо на shared; (c) `.env` и `private/zsh/*.sh` сорсятся в каждую сессию, но не аудированы (вне scope); `ANTHROPIC_AUTH_TOKEN=lmstudio` — dummy-плейсхолдер для localhost, не credential.
5. **orbstack — `docker.expose_ports_to_lan=true`** без justification-комментария, которого требует собственный security.md (документировать security-исключения); плюс дефолтный `machines.expose_ports_to_lan=true` тоже открывает порты в LAN. Для личной машины в домашней сети приемлемо — задокументировать.
6. **Чисто без оговорок:** aerospace, btop, k9s (мутирующий argocd-sync корректно за `confirm:true`), lazygit, leader-key, lnav, starship, tmux.
