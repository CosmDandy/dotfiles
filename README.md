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

# Логи установки

Работает на обеих платформах: запись включает корневой `install.sh`.
Каждый прогон пишется целиком в
`~/.local/state/dotfiles/install-<дата>-<время>.log`; `install-last.log` —
симлинк на последний. Путь печатается первой и последней строкой прогона.
Хранятся десять последних.

В шапке лога: дата, хост с архитектурой, пользователь, коммит репозитория и
профиль. Без них два лога невозможно сравнить, а это единственное, зачем их
обычно открывают.

```bash
tail -f ~/.local/state/dotfiles/install-last.log   # смотреть идущую установку
grep -iE 'warn:|error|FATAL' ~/.local/state/dotfiles/install-last.log
```

Цвет из лога не вычищается: BSD и GNU `sed` по-разному буферизуют строки, а
наполовину записанный лог хуже цветного. Читать — `less -R`.

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

# NixOS-стенд (Proxmox, VMID 9002)

Пользовательский слой тот же — `platform/nix/home/`, профили core/devops. Новое
здесь только системное: `platform/nix/nixos/` и `nixosConfigurations.nixos-stand`
в `platform/nix/flake.nix`. `platform/linux/install.sh` не участвует вообще, и
apt-минимума (`zsh git xz-utils curl`) тоже нет — ставить его нечем и незачем.

Поднятие с нуля из клона убунтовой VM на ноде:

```bash
ssh pve-local-l-02
qm clone 9000 9002 --name nixos-stand --full 1 --storage ssd-stripe
qm set 9002 --cores 8 --memory 49152      # см. про память ниже
qm resize 9002 scsi0 +24G
qm start 9002
```

Адрес — по MAC из `qm config 9002` после пинг-свипа /24. Дальше nixos-anywhere:
он kexec'ает работающую Ubuntu в NixOS-инсталлятор, размечает диск через disko и
ставит систему.

```bash
# cloud-init кладёт ключ только пользователю, а nixos-anywhere ходит рутом
ssh cosmdandy@<ip> 'sudo cp ~/.ssh/authorized_keys /root/.ssh/authorized_keys'

cd platform/nix
# фазой kexec отдельно: после неё адрес меняется (см. ниже), и нужен новый
nix run github:nix-community/nixos-anywhere -- --flake .#nixos-stand \
  --build-on-remote --phases kexec --target-host root@<ip>
nix run github:nix-community/nixos-anywhere -- --flake .#nixos-stand \
  --build-on-remote --phases disko,install,reboot --target-host root@<новый ip>
```

Повторное применение — `nixos-rebuild`, не `home-manager switch`: home-manager
здесь модуль NixOS, ровно как на macOS внутри `darwin-rebuild`.

```bash
cd platform/nix && nixos-rebuild switch --flake .#nixos-stand \
  --target-host root@<ip> --build-host root@<ip>
# или изнутри стенда:
sudo nixos-rebuild switch --flake ~/dotfiles/platform/nix#nixos-stand
```

Грабли, каждая проверена на этом стенде:

- `--build-on-remote` обязателен: мак — aarch64-darwin, x86_64-linux локально не
  собирается.
- Память на время установки. Store kexec-инсталлятора — tmpfs в половину RAM, и
  всё замыкание системы проезжает через него, прежде чем лечь на диск. Замер: на
  16 ГБ это 7,9 ГБ store при замыкании 4,7 ГиБ плюс сборочный мусор — впритык
  настолько, что проверять не стали и подняли VM до 48 ГБ (24 ГБ store, с
  запасом). После установки стенд живёт на 16 ГБ: пересборка идёт уже на диске.
- Адрес уезжает при смене ОС. Ubuntu просит DHCP по MAC, dhcpcd и
  systemd-networkd — по сгенерированному DUID, поэтому та же машина получает
  вторую аренду (у нас .206 → .209 прямо посреди установки, пока nixos-anywhere
  ждал старый адрес). В конфиге лечится `networking.dhcpcd.extraConfig =
  "clientid"`, но kexec-инсталлятор до этой настройки не доживает — его адрес
  ищется заново.
- BIOS, не UEFI: у VM нет `efidisk0`, внутри нет `/sys/firmware/efi`. Поэтому в
  `nixos/disk.nix` раздел EF02 под GRUB и нет ESP. `boot.loader.grub.devices` не
  задаётся — его выводит disko, второе присваивание валит сборку на
  `duplicated devices in mirroredBoots`.
- Консоль на `ttyS0` включена намеренно: `qm terminal 9002` — единственный вход,
  когда сеть или sshd сломаны, и без serial в GRUB неудачное поколение нечем
  откатить.

Чем стенд отличается от Ubuntu:

- Системный слой декларативный. Шелл, таймзона, локаль, sshd, sudo — не `chsh` и
  не `ln -sf /usr/share/zoneinfo/...` в конце install.sh, а опции NixOS.
- `programs.nix-ld.enable` — единственное, что на Ubuntu достаётся даром.
  Готовые бинарники (пакеты mason, инсталлятор Claude Code) ищут
  `/lib64/ld-linux-x86-64.so.2`, которого в NixOS нет.
- Рабочую копию клонирует systemd-юнит `dotfiles-clone` перед home-manager:
  `home/files.nix` симлинкает всё в `~/dotfiles`, и без клона home — это набор
  битых ссылок, а хуки nvim/mason молча пропускают себя. Клон по https, ключа к
  github у стенда нет — сабмодули `private/` и `tools/claude/custom`
  подтягиваются руками, с проброшенным агентом.
- `gcc` из `home/default.nix` нужен ровно так же, как на голой Ubuntu: без
  компилятора парсеры treesitter не собираются.

Замеры, 8 vCPU, профиль devops, всё из кеша кроме terraform (BUSL — в
`cache.nixos.org` его нет и он собирается на месте):

| | |
| --- | --- |
| kexec, включая скачивание образа инсталлятора | ~4 мин |
| `disko,install,reboot` | 17 мин |
| первая загрузка: клон репо + активация home-manager | 1 мин 48 с |
| повторный `nixos-rebuild switch` (хуки прогоняются заново) | 104 с |
| замыкание системы | 4,7 ГиБ |
| `/nix/store` на трёх поколениях | 6,0 ГБ |
| корень занят | 7,5 ГБ из 55 |

Что не работает и почему — обе причины к NixOS отношения не имеют:

- Инсталлятор Claude Code с этой сети недоступен: `claude.ai/install.sh`
  отдаёт HTML «App unavailable in region», хук видит невалидный скрипт и пишет
  `claude install skipped (offline?)`.
- `terraform-ls` не ставится: mason тянет
  `releases.hashicorp.com/terraform-ls/0.39.0/…zip`, а тот отдаёт 404. Реестр
  mason указывает на исчезнувшую версию — на Ubuntu будет ровно то же.

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
