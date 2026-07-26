# TODO

Актуализировано 2026-07-26 по ревизии памяти, git-истории и сессий за две недели.
Старый список (post-merge миграции на home-manager) закрыт полностью: ветки
влиты, ghcr-образ публичный, профили core/devops, kvt-d-01 мигрирован.

## Безопасность / секреты (приоритет)

- [ ] **Restic**: первый снапшот запущен 26.07 — проверить, что дошёл
      (`restic snapshots`). Дальше: еженедельный
      `restic check --read-data-subset=5%`, нотификация о молчаливом падении
      (лог сейчас в /tmp — умирает при ребуте), квартальный restore-drill
- [ ] Отозвать старые токены: 12 GitHub PAT + 2 OpenAI (`Experiments/result.json`,
      2023), 2 токена Obsidian-плагинов (`KnowledgeBase`). Разбирает владелец сам
- [ ] Убрать plaintext-секреты с диска: `~/Projects/secrets.tfvars`
      (hcloud/cloudflare/github, март 2026) и `~/.deepgram_key` → rbw/sops + ротация
- [ ] trivy в мягком режиме (`exit-code: "0"`) в local-lab, cloud-lab, pxe-server —
      разобрать ~30 находок (владелец сам), потом переключить на `"1"`
- [ ] Сменить засвеченные пароли: IMM x3550 (user cosmdandy) + отключить дефолтный
      USERID; root Proxmox на T30 (192.168.20.152)
- [ ] local-lab: вписать реальные секреты в `secrets.sops.yaml` вместо
      `REPLACE-*`, ротировать proxmox-токены, `ansible-galaxy install`
- [ ] pxe-server: секреты из defaults → SOPS
- [ ] YubiKey (когда дойдёт): сначала FIDO2 (GitHub/почта/Bitwarden, два ключа),
      потом `ed25519-sk` + age-plugin-yubikey

## Homelab / железо

- [ ] x3550 M3: переустановить Proxmox свежим ISO (стоит PVE 7, EOL) пока полигон
      пуст; рабочий диск первым в Boot Order; POST Watchdog on, Quiet Boot off;
      проверить финальную прошивку IMM/UEFI; второй БП
- [ ] Capstone: PXE → Talos (`console=ttyS0`!) → single-node k8s только с мака
- [ ] Перенести PXE-роль на x3550 как постоянный сервер (Wi-Fi-мост невозможен
      принципиально — см. память)
- [ ] pxe-server: wipe-профиль на Alpine (~50 МБ) вместо ubuntu-installer (3 ГБ)

## Обучение (Kubestronaut)

- [ ] /lab не используется — ledger пуст: снизить трение privileged-devcontainer
      до одной команды, прогнать первый drill
- [ ] k8s-арена: kubeadm+Ubuntu на офисном Proxmox (НЕ Talos), snapshot-reset
      через `qm rollback`, скрытая ground truth, агент не даёт решений
- [ ] Порядок сертов: CKA первым, killer.sh обязателен

## macOS / dotfiles

- [ ] Чистка комментариев-сессионного шума по репо (триаж: constraint остаётся,
      нарратив/декоративные заголовки — удаляются). Задача уровня Sonnet
- [ ] При следующем реальном `updm` с бампом пинов — прогнать в UTM-VM
      (реальный сдвиг flake.lock тестами не покрыт)

## Известные tradeoffs (осознанные, фиксов не требуют)

- Claude Code сознательно НЕ через nix: официальный бинарь самообновляется
- PR в репозитории отключены, прямой push в main — везде
- lazy-lock.json отвергнут: `install + clean + update` вместо пина
- Коммиты по-русски — конвенция; перевод истории обсуждён и отложен
- Декларативность не догма: GUI-приложения типа Analog ставятся руками
- SQL-клиент: выбран Postico (cask), lazysql снят с повестки
- Автообновление Claude Code оставлено включённым — владельца устраивает
- Starship-индикаторы: текущего набора (контейнер + VM) достаточно,
  `[custom.ansible]` и `[os]` отклонены
