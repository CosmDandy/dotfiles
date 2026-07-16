# TODO после миграции на home-manager + prebuilt-образ

## Сразу после merge в master

- [ ] **На маке перед `git pull`**: удалить локальный `platform/nix/flake.lock`
      (он untracked и будет мешать pull'у — в master теперь приезжает
      закоммиченная версия с пином home-manager):
      `rm ~/.dotfiles/platform/nix/flake.lock && git -C ~/.dotfiles pull`
- [ ] Дождаться первого рана workflow `devcontainer-image` (соберёт и запушит
      `ghcr.io/cosmdandy/devcontainer:full`, ~30–50 мин)
- [ ] **Однократно**: сделать ghcr-пакет `devcontainer` публичным —
      GitHub → Packages → devcontainer → Package settings → Change visibility →
      Public. Без этого `devpod up` упадёт на анонимном pull образа
- [ ] Пересоздать существующие devpod-workspace'ы: они легаси (nix-env),
      cron-обновление их пропускает с пометкой в логе
- [ ] Смержить ветку `worktree-direnv-rbw` (direnv/rbw): конфликт в
      `.gitignore`/`flake.lock` тривиален — обе ветки снимают lock с ignore

## Известные tradeoffs (осознанные, фиксов не требуют)

- После бампа `flake.lock` ночной cron пересобирает terraform (unfree, нет в
  cache.nixos.org) в каждом живом full-контейнере — дешевле пересоздать
  workspace (образ к этому моменту уже пересобран CI). Долгосрочно: свой
  бинарный кэш (cachix / ghcr as nix cache)
- Prebuilt-образ собирается только для full-профиля; base идёт путём
  «голый образ + install.sh» (~3.5 мин, всё из бинарного кэша)
- Claude Code сознательно НЕ через nix: официальный бинарь самообновляется,
  activation-хук лишь ставит его при отсутствии

## Дальше (по приоритету)

- [ ] **Секреты**: rbw + direnv (ветка уже есть), sops + age для секретов
      в репозиториях, YubiKey — ssh-ключи `ed25519-sk` (переживают снос
      ноутбука) и `age-plugin-yubikey` как hardware root of trust
- [ ] **macOS-развёртка в UTM**: базовая VM (Remote Login + pubkey,
      NOPASSWD sudo, диск для клонов в APFS — `cp -c` клонирует мгновенно) →
      headless-прогон `platform/macos/install.sh`, карта интерактивных
      точек (`confirm()`, 32× `setup_app` в install-extra.sh) → фиксы
- [ ] **Per-project devShells**: flake.nix c devShell в рабочих репо +
      nix-direnv; глобальный full-профиль постепенно худеет до личных
      инструментов, версии проектов перестают конфликтовать
- [ ] lazysql в full-профиль + конфиг подключений к базам
- [ ] Ревизия репо: `tools/pandoc` (конфиг неустановленного инструмента),
      `tools/vscode` (не тронут с февраля; в casks три редактора), дубли
      casks (chatgpt/claude/lm-studio, utm/orbstack), argocd vs fluxcd,
      talosctl (есть ли кластеры), iperf3 в base-профиле
- [ ] macOS: перевод `platform/macos/install.sh` на home-manager
      (после обкатки схемы на Linux и UTM-тестов)
