# Секреты и окружение

Цель: секреты не лежат plaintext'ом в `~/.dotfiles/.env`, который сорсится глобально в каждый шелл и целиком уезжает в каждый dev-контейнер. Секреты живут в Bitwarden, достаются `rbw` и попадают в окружение только того проекта, где нужны (`direnv`).

Модель: **хост — trust anchor**, контейнеры — потребители. Vault разблокируется только на хосте; контейнер получает готовые переменные и мастер-пароль не видит. Отсюда же деление: `EDITOR=nvim` — конфиг (можно коммитить), `JIRA_API_TOKEN` — секрет (только vault).

## Стек

| Компонент | Роль | Где объявлен |
|---|---|---|
| `rbw` | CLI к Bitwarden; агент держит vault расшифрованным в памяти | `platform/nix/darwin-configuration.nix` |
| `pinentry-mac` | Диалог мастер-пароля для rbw | там же |
| `direnv` + `nix-direnv` | Окружение из `.envrc` при `cd`; кэш `use flake` | там же + hook в `tools/zsh/.zshrc`, `tools/direnv/direnvrc` |
| `gitleaks` | Скан секретов в pre-commit | `tools/git/hooks/pre-commit` |
| Конфиг rbw | email, `lock_timeout`, pinentry | `~/.dotfiles-private/rbw/config.json` → симлинк |
| Trust Homebrew | Доверие к сторонним tap | `tools/homebrew/trust.json` → симлинк на два пути |

## Что настроить

1. `sudo darwin-rebuild switch --flake ~/.dotfiles/platform/nix#macbook-cosmdandy`
2. `rbw register` — **обязательно до login** (см. грабли), спросит API-ключ
3. `rbw login`
4. Разложить 4 секрета из `.env` в Bitwarden: `JIRA_API_TOKEN`, `GITLAB_TOKEN`, `NOMAD_TOKEN`, `OPENSEARCH_PASS`. Остальные 5 (`JIRA_URL`, `JIRA_USERNAME`, `NOMAD_ADDR`, `OPENSEARCH_USER`, `TIMING_MCP_URL`) — конфиг, остаются в `.env`.
5. Манифесты `env/*.env.tpl` (имена + ссылки `@rbw:`, без значений) → функция `env-render` → `dpl`/`dpf` через `--workspace-env-file <(env-render …)` → слои `.envrc`.

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

Слои — это каталоги, ищется ближайший `.envrc`:

```sh
~/work/.envrc        # «нужно всегда на работе»
  export JIRA_TOKEN=$(rbw get kvt-jira)
~/work/repo/.envrc   # специфика проекта
  source_up           # ← иначе заменит родительский, а не дополнит
  use flake
~/homelab/.envrc
  export PROXMOX_TOKEN=$(rbw get homelab-proxmox)
```

Командный паттерн: `.envrc` коммитится и содержит только несекретное + `source_env_if_exists .envrc.local`; личное — в `.envrc.local` (добавить в глобальный gitignore). Контракт — имена переменных, способ добычи у каждого свой.

## Грабли (проверено)

- **`rbw login` → 400.** Причина видна в `agent.err`: `New device verification required` — официальный сервер режет CLI-трафик. Лечится `rbw register` с персональным API-ключом: web-vault → Settings → Security → Keys → View API key. Только в вебе, в десктоп-приложении этой страницы нет. `client_secret` на диск не пишется (используется один раз, живёт в locked-памяти).
- **Touch ID с rbw невозможен.** `pinentry-touchid` включает биометрию только при `len(KeyInfo) != 0 && AllowExtPasswdCache`; rbw шлёт лишь `GETPIN`/`SETPROMPT`/`SETDESC`. Форк lujstn — то же условие. Кэш Keychain у `pinentry-mac` требует того же. Итог: мастер-пароль руками раз в `lock_timeout`.
- **rbw на macOS игнорирует `XDG_CONFIG_HOME`** и читает `~/Library/Application Support/rbw/config.json`. Симлинк в `~/.config/rbw` — мёртвый.
- **`brew trust` пишет не туда.** Активация nix-darwin вызывает `sudo --preserve-env=PATH`, `XDG_CONFIG_HOME` теряется → brew читает `~/.homebrew/trust.json`, а интерактивный шелл — `~/.config/homebrew/trust.json`. Поэтому симлинки на оба пути; brew пишет сквозь симлинк, не подменяя его.
- **`flake.lock` нельзя держать в `.gitignore`** — nix исключает игнорируемые файлы из git-флейка, и пины молча не работают. nixpkgs и nix-darwin двигать парой; проверять кэш: `nix build nixpkgs#blueutil --max-jobs 0`.
- **`bitwarden-desktop` из nixpkgs** тянет electron, помеченный insecure → ставится каском.
- **SSH:** `ControlMaster` + `ControlPersist 10m` в `~/.ssh/config` — одно подтверждение ключа на хост вместо подтверждения на каждую команду. Нужен каталог `~/.ssh/sockets` (создаёт `setup-symlinks.sh`).

## Известные проблемы

- **gitleaks не работает в самом dotfiles-репо**: в `.git/config` `core.hooksPath` переопределён на пустой `.git/hooks` (глобально — `~/.git-hooks`, там хук есть).
- **Приватный репозиторий склонирован дважды**: `~/.dotfiles-private` (на него смотрят симлинки) и подмодуль `~/.dotfiles/private` — один remote, разные незакоммиченные правки. Копии разъедутся и затрут друг друга.
