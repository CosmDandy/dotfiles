# DFU Mode

[![Open in GitHub Codespaces][codespaces]](https://codespaces.new/CosmDandy/dotfiles)

[![build][build]](https://github.com/CosmDandy/dotfiles/actions/workflows/test-install.yml) [![scorecard][scorecard]](https://scorecard.dev/viewer/?uri=github.com/CosmDandy/dotfiles) [![SLSA][SLSA]](https://slsa.dev) [![nix][nix]](https://nixos.org) [![license][license]](LICENSE)

Control + Option + Shift + Power (MacBook Air M1)

# Установка

1. Заходим в Safari и логинимся в GitHub
Входим в tailscale
sudo rm /etc/zshenv добовляем удаление подобного говна
3. Выполняем код ниже и закидываем ключ в поле

```bash
# первый вызов git предложит поставить CLT (или это сделает install.sh сам,
# headless-совместимо); Rosetta и сабмодули install.sh тоже ставит сам
read "key_path?Enter path to SSH private key: "
export GIT_SSH_COMMAND="ssh -i $key_path"
git clone git@github.com:CosmDandy/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

Приватные конфиги (ssh, rbw, env) едут сабмодулем `private/` — отдельный клон
`~/.dotfiles-private` больше не нужен. Интерактивная настройка приложений:
`platform/macos/install-extra.sh` (в headless-прогоне пропускается автоматически).

Пользовательское окружение (симлинки конфигов, devpod, orbstack, Claude Code,
MCP) на macOS управляется home-manager внутри `darwin-rebuild switch` — те же
модули `platform/nix/home/`, что и на Linux. Повторное применение: `updm`.

# Linux (голая Ubuntu, OrbStack-машина)

Пребилт-образ `ghcr.io/cosmdandy/devcontainer` всё системное уже несёт
(`platform/linux/Dockerfile`). На голой Ubuntu до `./install.sh` руками ставится
только то, что не может поставить home-manager — он работает от пользователя и
приезжает уже после Nix:

```bash
sudo apt update && sudo apt install -y zsh git xz-utils curl
git clone git@github.com:CosmDandy/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh          # PROFILE=core — облегчённый профиль
```

Зачем каждый пакет (без него — так падает):

- `zsh` — shebang `install.sh`; без него `bad interpreter`. Плюс `chsh` в конце.
- `git` — клон репо, сабмодуль `private/` (без него install.sh падает намеренно),
  `git ls-tree`. Тянет за собой `perl`, откуда `shasum` для инсталлятора Claude Code.
- `xz-utils` — инсталлятор Nix распаковывает тарболл: `you do not have 'xz'
  installed`. Пакет называется именно `xz-utils`, `apt install xz` не найдёт.
- `curl` — сам инсталлятор Nix и хуки (Claude Code, zinit, схемы CRD).
- `sudo` — `mkdir /nix`, `/etc/shells`, `chsh`, таймзона. Есть в любой Ubuntu.
- Локаль `en_US.UTF-8` — в образе OrbStack и на сервере уже есть; в docker-образе
  `ubuntu` нужны `locales` + `locale-gen` (см. Dockerfile).

Всё остальное (nvim, node, python, go, terraform, kubectl…) — из `flake.lock`
через home-manager.

## Режим установки Nix: контейнер против системы

`install.sh` выбирает форму установки сам, по наличию systemd
(`/run/systemd/system`), и печатает выбор строкой `Installing Nix (…-user)`.
Переопределяется переменной: `NIX_INSTALL=single|multi ./install.sh`.

| | `single` | `multi` |
| --- | --- | --- |
| Где | devcontainer, образ CI | сервер, VM, машина OrbStack |
| Владелец `/nix` | пользователь | root |
| `nix-daemon` | нет | есть, сборки в песочнице от `nixbld` |
| Что нужно среде | ничего | systemd и root на время установки |

Смысл разделения. Демону нужен init, который его надзирает, — в контейнере его
нет, поэтому там остаётся однопользовательская форма, и это не компромисс:
контейнер изолирован сам по себе, а хранилище делить не с кем. На долгоживущей
машине, где лежат рабочие ключи, всё наоборот: сборка не должна идти с правами
пользователя, а подпись содержимого хранилища должна что-то значить.

Определение идёт по systemd, а не по признакам контейнера: машина OrbStack по
всем маркерам выглядит контейнером (`/opt/orbstack-guest`, нет железа), но это
полноценная система с systemd, и демон ей полагается.

При `multi` скрипт дописывает в `/etc/nix/nix.conf` `experimental-features` и
`trusted-users` и перезапускает демон — без второго демон молча игнорирует
переданные пользователем `substituters`, и единственный симптом это пересборка
там, где ожидалось попадание в кеш.

Смена формы на уже установленной машине — это переустановка nix, а не флаг:
`/nix` меняет владельца. Проверить, что стоит сейчас: `ls -ld /nix` и
`systemctl is-active nix-daemon`.

Особенности машины OrbStack (`orb create ubuntu <имя>`), проверено на 26.04:

- Это `ubuntu-minimal` (~260 пакетов), не Ubuntu Server: нет ядра, grub,
  cloud-init, snapd, openssh-server, `ubuntu-standard`. Ядро общее OrbStack'овское,
  корень — btrfs-subvolume на общем диске, мак смонтирован в `/mnt/mac`.
  Репозитории apt те же, что у обычной Ubuntu, — всё, что ставится, ведёт себя
  одинаково. Сверх минимума OrbStack сам доставил `fuse3 curl openssh-client sudo
  vim language-pack-en systemd-resolved systemd-timesyncd`.
- ssh-агент мака проброшен автоматически (`SSH_AUTH_SOCK` →
  `/opt/orbstack-guest/run/host-ssh-agent.sock`) — сабмодули `private/` и
  `tools/claude/custom` подтягиваются без дополнительной настройки.
- Docker CLI в машине нет и сокет в `/var/run` не проброшен — ставить отдельно,
  если нужен.
- Пользователь создаётся с uid мака (501), а не 1000 — для машины это неважно,
  для devpod-контейнеров см. `updateRemoteUserUID` в `.devcontainer/`.
- Память у всех машин общая, лимит в `tools/orbstack/apply.sh`; `home-manager
  switch` профиля devops на 4 ГБ / 6 vCPU идёт больше пяти минут.

balena etcher
Office 2024
wispr flow
wakatime
телемост
remote desktop
meta
sound id reference

[codespaces]: https://github.com/codespaces/badge.svg
[build]: https://img.shields.io/github/actions/workflow/status/CosmDandy/dotfiles/test-install.yml?branch=main&style=flat&label=build&labelColor=21262d&logo=githubactions&logoColor=8b949e
[scorecard]: https://img.shields.io/ossf-scorecard/github.com/CosmDandy/dotfiles?style=flat&label=scorecard&labelColor=21262d
[SLSA]: https://img.shields.io/badge/SLSA-3-7828dc?style=flat&labelColor=21262d&logo=data%3Aimage%2Fpng%3Bbase64%2CiVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAMAAAAolt3jAAAABGdBTUEAALGPC%2FxhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAABMlBMVEXvMQDvMADwMQDwMADwMADvMADvMADwMADwMQDvMQDvMQDwMADwMADvMADwMADwMADwMQDvMQDvMQDwMQDvMQDwMQDwMADwMADwMQDwMADwMADvMADvMQDvMQDwMADwMQDwMADvMQDwMADwMQDwMADwMADwMADwMADwMADwMADvMQDvMQDwMADwMQDwMADvMQDvMQDwMADvMQDvMQDwMADwMQDwMQDwMQDvMQDwMADvMADwMADwMQDvMQDwMADwMQDwMQDwMQDwMQDvMQDvMQDvMADwMADvMADvMADvMADwMQDwMQDvMADvMQDvMQDvMADvMADvMQDwMQDvMQDvMADvMADvMADvMQDwMQDvMQDvMQDvMADvMADwMADvMQDvMQDvMQDvMADwMADwMQDwMAAAAAA%2FHoSwAAAAY3RSTlMpsvneQlQrU%2FLQSWzvM5DzmzeF9Pi%2BN6vvrk9HuP3asTaPgkVFmO3rUrMjqvL6d0LLTVjI%2FPuMQNSGOWa%2F6YU8zNuDLihJ0e6aMGzl8s2IT7b6lIFkRj1mtvQ0eJW95rG0%2BSid59x%2FAAAAAWJLR0Rltd2InwAAAAlwSFlzAAAOwwAADsMBx2%2BoZAAAAAd0SU1FB%2BYHGg0tGLrTaD4AAACqSURBVAjXY2BgZEqGAGYWVjYGdg4oj5OLm4eRgZcvBcThFxAUEk4WYRAVE09OlpCUkpaRTU6WY0iWV1BUUlZRVQMqUddgSE7W1NLS1gFp0NXTB3KTDQyNjE2Sk03NzC1A3GR1SytrG1s7e4dkBogtjk7OLq5uyTCuu4enl3cyhOvj66fvHxAIEmYICg4JDQuPiAQrEmGIio6JjZOFOjSegSHBBMpOToxPAgCJfDZC%2Fm2KHgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyMi0wNy0yNlQxMzo0NToyNCswMDowMC8AywoAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjItMDctMjZUMTM6NDU6MjQrMDA6MDBeXXO2AAAAGXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm%2B48GgAAAABJRU5ErkJggg%3D%3D
[nix]: https://img.shields.io/badge/nix-flake-00a8c8?style=flat&labelColor=21262d&logo=nixos&logoColor=8b949e
[license]: https://img.shields.io/github/license/CosmDandy/dotfiles?style=flat&label=license&labelColor=21262d&color=484f58&logo=opensourceinitiative&logoColor=8b949e
