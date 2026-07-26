# Секреты и окружение

Цель: секреты не лежат plaintext'ом в `~/.dotfiles/.env`, который сорсится глобально в каждый шелл и целиком уезжает в каждый dev-контейнер. Секреты живут в Bitwarden, достаются `rbw` и попадают в окружение только того проекта, где нужны (`direnv`).

Модель: **хост — trust anchor**, контейнеры — потребители. Vault разблокируется только на хосте; контейнер получает готовые переменные и мастер-пароль не видит. Отсюда же деление: `EDITOR=nvim` — конфиг (можно коммитить), `JIRA_API_TOKEN` — секрет (только vault).

Два хранилища под разные секреты:

- **rbw / Bitwarden** — секреты, общие между проектами (Jira, GitLab, OpenSearch) и мастер-ключи (age-ключ, пароли).
- **SOPS + age** — секреты, относящиеся к одному проекту (Proxmox-токен, пароли сервисов): лежат **зашифрованными в самом git-репозитории** проекта рядом с кодом.

Правило: *общее между проектами → rbw; принадлежит проекту → sops в его репо.*

## Стек

| Компонент | Роль | Где объявлен |
|---|---|---|
| `rbw` | CLI к Bitwarden; агент держит vault расшифрованным в памяти | `platform/nix/darwin-configuration.nix` |
| `pinentry-mac` | Диалог мастер-пароля для rbw | там же |
| `direnv` + `nix-direnv` | Окружение из `.envrc` при `cd`; кэш `use flake` | там же + hook в `tools/zsh/.zshrc`, `tools/direnv/direnvrc` |
| `sops` | Шифрует значения в структурированных файлах (YAML/JSON/env) для хранения в git | `platform/nix/darwin-configuration.nix` |
| `age` | Движок шифрования, на котором работает sops; ключ — в `~/.config/sops/age/keys.txt` | там же |
| `gitleaks` | Скан секретов в pre-commit | `tools/git/hooks/pre-commit` |
| Конфиг rbw | email, `lock_timeout`, pinentry | `~/.dotfiles/private/rbw/config.json` (сабмодуль) → симлинк |
| Trust Homebrew | Доверие к сторонним tap | `tools/homebrew/trust.json` → симлинк на два пути |

## Что настроить

1. `sudo darwin-rebuild switch --flake ~/.dotfiles/platform/nix#macbook-cosmdandy`
2. `rbw register` — **обязательно до login** (см. грабли), спросит API-ключ
3. `rbw login`
4. Разложить 4 секрета из `.env` в Bitwarden: `JIRA_API_TOKEN`, `GITLAB_TOKEN`, `NOMAD_TOKEN`, `OPENSEARCH_PASS`. Остальные 5 (`JIRA_URL`, `JIRA_USERNAME`, `NOMAD_ADDR`, `OPENSEARCH_USER`, `TIMING_MCP_URL`) — конфиг, остаются в `.env`.
5. Манифесты `env/*.env.tpl` (имена + ссылки `@rbw:`, без значений) → функция `env-render` → `dpl`/`dpf` через `--workspace-env-file <(env-render …)` → слои `.envrc`.
6. Для проектных секретов — age-ключ: `age-keygen -o ~/.config/sops/age/keys.txt` (один раз), публичный ключ → в `.sops.yaml` проекта, приватный → бэкап в rbw. Подробно — раздел «SOPS + age».

Конвенция имён в Bitwarden: `<контекст>-<сервис>` — `kvt-jira`, `homelab-proxmox`. Одиночный токен — в поле password (тогда `rbw get` отдаёт его без флагов), составные креды — custom hidden fields. URL'ы и прочее несекретное в vault не класть.

## rbw

```sh
rbw unlock              # раз в lock_timeout (сейчас 1 час)
rbw get kvt-jira        # секрет в stdout
rbw get --field=host X  # custom field
rbw code kvt-gitlab     # TOTP-код
rbw config show         # эффективный конфиг
```

Регистрация привязана к устройству — на каждой новой машине `rbw register` заново.

## direnv / .envrc

Механика: hook в zsh перед каждым промптом спрашивает direnv; тот ищет `.envrc` вверх по дереву, выполняет его **в отдельном bash-процессе**, снимает дифф окружения и накладывает на шелл. При выходе из каталога — откатывает. В шелл попадают только переменные, не алиасы и функции. Пересчёт — только при входе в каталог и при изменении `.envrc`, поэтому `rbw get` внутри дёргается один раз на вход, а не на каждый промпт.

`direnv allow` — защита: чужой `.envrc` не выполнится, пока не разрешишь явно; после каждой правки блокируется снова.

### Слои и `source_up`

`.envrc` нужен **не в каждой папке**, а там, где меняется набор переменных. direnv сам ищет ближайший файл вверх по дереву, поэтому подпапки наследуют его бесплатно.

```sh
~/work/.envrc              # «нужно всегда на работе»
  export JIRA_TOKEN=$(rbw get kvt-jira)
~/work/repo-a/             # своего .envrc НЕ нужно — подхватит родительский
~/work/repo-b/.envrc       # нужен, только если есть что добавить
  source_up                # ← без этой строки родительский НЕ подтянется
  use flake
```

**`source_up` — ключевая деталь.** По умолчанию direnv грузит **только ближайший** `.envrc`, а не всю цепочку. Если у листа есть свой файл, родительский он **заменяет**, а не дополняет. `source_up` первой строкой возвращает наследование: сначала выполнится родитель, потом лист.

Отсюда правило против дублирования: **секрет достаётся один раз наверху, листья только раскладывают его по именам.**

```sh
project/.envrc                       # ← ЕДИНСТВЕННОЕ место с обращением к хранилищу
  export PVE_LOCAL_TOKEN=$(sops -d --extract '["pve_local_token"]' ...)
  export PVE_KLG_TOKEN=$(sops -d --extract '["pve_klg_token"]' ...)

project/terraform/live/pve-local-l/.envrc
  source_up                                        # подтянуть пул
  export TF_VAR_proxmox_api_token=$PVE_LOCAL_TOKEN # просто маппинг, без sops/rbw

project/terraform/live/pve-klg-p-02/.envrc
  source_up
  export TF_VAR_proxmox_api_token=$PVE_KLG_TOKEN
```

Так одинаковое имя `TF_VAR_proxmox_api_token` в обеих папках получает **разное** значение — конфликт разрешается расположением. Считать надо не файлы, а обращения к хранилищу: листовых `.envrc` может быть много (это дешёвая проводка, в них нет секретов), а `sops -d`/`rbw get` — единицы. Если видишь скопированный из соседа блок с `rbw get` — выноси выше.

Командный паттерн: `.envrc` коммитится и содержит только несекретное + `source_env_if_exists .envrc.local`; личное — в `.envrc.local` (добавить в глобальный gitignore). Контракт — имена переменных, способ добычи у каждого свой.

## SOPS + age

**Зачем.** rbw хорош для секретов, что нужны в разных проектах. Но секрет, принадлежащий одному проекту (Proxmox-токен, пароль сервиса), логичнее держать **в его репозитории** — рядом с кодом, версионированным. Просто plaintext туда нельзя, поэтому шифруем: `sops` шифрует **только значения**, оставляя имена полей читаемыми, а `age` — движок шифрования под ним.

```yaml
# так secrets.sops.yaml выглядит в git — имя видно, значение зашифровано
pve_local_token: ENC[AES256_GCM,data:0zlz...,type:str]
```

Отсюда плюс перед ansible-vault (который шифровал файл целиком): `git diff` показывает, *какое поле* изменилось, не раскрывая значений.

**age-ключ — корень доверия.** Один keypair. Приватный лежит файлом `~/.config/sops/age/keys.txt` (права 600) — это стандартное место, sops находит его сам. Публичный (`age1...`) — не секрет, вписывается в `.sops.yaml`. Класс секрета — как SSH-ключ: файл 600 это норма, а не дыра. Бэкап приватного — в rbw (`sops-age-key`): потеря файла = потеря доступа ко всем зашифрованным секретам.

### Два файла: конфиг и данные

Имена похожи до путаницы, но это **разные вещи**:

| Файл | Что это | Секреты внутри? |
|---|---|---|
| `.sops.yaml` (точка в начале, корень проекта) | **Конфиг**: кому можно читать | нет — только публичный ключ и правила |
| `secrets.sops.yaml` (и любые `*.sops.yaml`) | **Данные**: сами секреты, зашифрованные | да, но в виде шифротекста |

Мнемоника: **`.sops.yaml` — «кому можно читать», `*.sops.yaml` — «что читать»**.

**Конфиг** — правило «что и на какой ключ шифровать»:

```yaml
# .sops.yaml
creation_rules:
  - path_regex: \.sops\.yaml$   # какие файлы подпадают под правило
    age: age1...                # публичный ключ-получатель (не секрет)
```

Получателей может быть несколько (ты, YubiKey, CI) — тогда файл расшифровывается любым из ключей, и общий пароль шарить не нужно. После правки `.sops.yaml` существующие файлы перешифровываются командой `sops updatekeys`.

**Имя файла с данными — соглашение, а не требование.** sops смотрит только на `path_regex`. Суффикс `.sops.yaml` удобен тем, что сразу видно «зашифрован», и одно правило ловит их все. Файлов с секретами может быть много (`terraform/secrets.sops.yaml`, `ansible/inventory/group_vars/all/secrets.sops.yaml`), а `.sops.yaml` — один на проект.

### Анатомия зашифрованного файла

Был обычный YAML → стал таким (и **это** лежит в git):

```yaml
pve_local_token: ENC[AES256_GCM,data:0zlz...,iv:GC8M...,tag:2tX/...,type:str]
sops:
    age:
        - recipient: age1xajxn80869y59...      # кто может расшифровать
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----  # ключ файла, зашифрованный на recipient
            ...
    mac: ENC[...]                               # защита от подмены значений
```

- **Имена полей открыты, значения зашифрованы** — отсюда читаемый `git diff`.
- Блок **`sops:`** дописывается автоматически: получатели, зашифрованный ключ файла, `mac`.
- Схема **гибридная**: содержимое шифруется случайным симметричным ключом, а сам он — твоим age-публичным. Поэтому добавление получателя не требует перешифровки данных.

### Цепочка: хранение → доставка → потребление

Файлов два, потому что у них разные роли: sops-файл **хранит**, `.envrc` **доставляет**.

```
secrets.sops.yaml            .envrc                       terraform
─────────────────            ──────                       ─────────
pve_local_token:        →    sops -d --extract       →    читает
  ENC[AES256...]             export TF_VAR_...            TF_VAR_proxmox_api_token
   (хранение, в git)          (доставка, в git)            (потребление)
```

Ключевое: **в `.envrc` нет ни одного значения — только команда его получения**, поэтому он коммитится открыто. И один sops-файл обслуживает много `.envrc` (см. пример со слоями выше: два кластера тянут разные ключи из одного файла).

Жизненный цикл:

```sh
# 1. создал обычный YAML со значениями
# 2. зашифровал — теперь безопасен для git
sops -e -i secrets.sops.yaml
# 3. дальше правишь только так (расшифрует в редактор, сохранит зашифрованным)
sops edit secrets.sops.yaml
# 4. .envrc достаёт одно значение при входе в каталог
```

Хранилище взаимозаменяемо: для общих секретов та же цепочка, только «рука» другая — `$(rbw get kvt-jira)` вместо `$(sops -d --extract ...)`.

**Команды (шпаргалка):**

```sh
sops -e -i secrets.sops.yaml                     # зашифровать файл на месте
sops edit secrets.sops.yaml                      # правка: расшифрует в редактор, сохранит зашифрованным
sops -d secrets.sops.yaml                        # расшифровать всё в stdout
sops -d --extract '["pve_local_token"]' f.yaml   # достать ОДНО значение (для .envrc)
sops updatekeys secrets.sops.yaml                # перешифровать после смены .sops.yaml (новый получатель)
```

**Связка с direnv** (проектный `.envrc` достаёт секрет из sops в переменную):

```sh
# terraform/live/pve-local-l/.envrc
ROOT="$(git rev-parse --show-toplevel)"
export TF_VAR_proxmox_api_endpoint="https://ip:8006/api2/json"   # конфиг — строкой
export TF_VAR_proxmox_api_token=$(sops -d --extract '["pve_local_token"]' "$ROOT/terraform/secrets.sops.yaml")
```

**Ansible** читает sops-файлы через vars-plugin — включается в `ansible.cfg`, дальше `group_vars/**/secrets.sops.yaml` расшифровываются автоматически:

```ini
[defaults]
vars_plugins_enabled = community.sops.sops,host_group_vars
```

(нужна коллекция: `community.sops` в `requirements.yml` + `ansible-galaxy install -r requirements.yml`)

**В dev-контейнере**: sops/age ставятся в образ, а приватный age-ключ **монтируется с хоста** read-only — ключ не запекается в слои, direnv+sops внутри работают как на хосте:

```jsonc
// devcontainer.json
"mounts": [
  "source=${localEnv:HOME}/.config/sops/age,target=/home/vscode/.config/sops/age,type=bind,readonly"
],
"remoteEnv": { "SOPS_AGE_KEY_FILE": "/home/vscode/.config/sops/age/keys.txt" }
```

## Что ещё есть (справочно, не внедрено)

- **passage + age-plugin-yubikey** — файловый менеджер паролей (форк `pass` на age), где приватный ключ живёт на YubiKey и каждый доступ требует тапа. Модель Filippo Valsorda. Апгрейд-путь, если появится юбик: тогда и age-ключ sops можно держать на железке, а не файлом.
- **Динамические / короткоживущие секреты** (Vault / OpenBao) — вместо «хранить токен надёжно» секрет **генерируется на лету с TTL** (напр. временный пользователь БД на 1 час) и авто-удаляется. Утёкший токен мёртв через час. Требует сервера (Vault/OpenBao) — шаг в инфраструктуру; для homelab полезно как рост, но не обязательно.

Полный разбор индустриальных практик и сравнение инструментов — в отчёте deep-research (эта сессия): консенсус = *vault + инжект на runtime, никогда не писать plaintext на диск*; наш стек (rbw+direnv+sops) ему соответствует.

## Грабли (проверено)

- **`rbw login` → 400.** Причина видна в `agent.err`: `New device verification required` — официальный сервер режет CLI-трафик. Лечится `rbw register` с персональным API-ключом: web-vault → Settings → Security → Keys → View API key. Только в вебе, в десктоп-приложении этой страницы нет. `client_secret` на диск не пишется (используется один раз, живёт в locked-памяти).
- **Touch ID с rbw невозможен.** `pinentry-touchid` включает биометрию только при `len(KeyInfo) != 0 && AllowExtPasswdCache`; rbw шлёт лишь `GETPIN`/`SETPROMPT`/`SETDESC`. Форк lujstn — то же условие. Кэш Keychain у `pinentry-mac` требует того же. Итог: мастер-пароль руками раз в `lock_timeout`.
- **rbw на macOS игнорирует `XDG_CONFIG_HOME`** и читает `~/Library/Application Support/rbw/config.json`. Симлинк в `~/.config/rbw` — мёртвый.
- **`brew trust` пишет не туда.** Активация nix-darwin вызывает `sudo --preserve-env=PATH`, `XDG_CONFIG_HOME` теряется → brew читает `~/.homebrew/trust.json`, а интерактивный шелл — `~/.config/homebrew/trust.json`. Поэтому симлинки на оба пути; brew пишет сквозь симлинк, не подменяя его.
- **`flake.lock` нельзя держать в `.gitignore`** — nix исключает игнорируемые файлы из git-флейка, и пины молча не работают. nixpkgs и nix-darwin двигать парой; проверять кэш: `nix build nixpkgs#blueutil --max-jobs 0`.
- **`bitwarden-desktop` из nixpkgs** тянет electron, помеченный insecure → ставится каском.
- **SSH:** `ControlMaster` + `ControlPersist 10m` в `~/.ssh/config` — одно подтверждение ключа на хост вместо подтверждения на каждую команду. Нужен каталог `~/.ssh/sockets` (создаёт activation-хук `sshSockets` в `platform/nix/home/darwin.nix`).

## Известные проблемы

- **gitleaks не работает в самом dotfiles-репо**: в `.git/config` `core.hooksPath` переопределён на пустой `.git/hooks` (глобально — `~/.git-hooks`, там хук есть).
- ~~**Приватный репозиторий склонирован дважды**~~ — исправлено: симлинки смотрят на сабмодуль `private/`, отдельный клон `~/.dotfiles-private` упразднён. Осталось руками: (1) закоммитить `rbw/config.json` из `~/.dotfiles-private` в master приватного репо (симлинк уже целится в `private/rbw/`, но в сабмодуле каталога ещё нет); (2) перенести прочие незакоммиченные правки и удалить `~/.dotfiles-private`.
