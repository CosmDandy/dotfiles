#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# ===============================
# Тонкий bootstrap: всё окружение (пакеты, симлинки, установщики) декларируется
# в platform/nix/home/ и применяется одним home-manager switch. Здесь остаётся
# только неустранимый минимум: nix, flakes, bridge-симлинк и system-уровень.
#
# Profiles: core | devops
# Usage: PROFILE=core ./install.sh
#    or: devpod up --dotfiles-script-env PROFILE=core
#
# Без явной переменной профиль берётся из маркера, который пребилт-образ пишет
# в ~/.dotfiles-profile (platform/linux/Dockerfile). Иначе на :core-образ
# разворачивался бы devops-профиль: home-manager тянул бы terraform, ansible,
# kubectl и k9s в персональный слой контейнера — ровно то, от чего уходили
# (замерено: 5м41с против ~20с). На голом образе без маркера — devops, как было.
# ===============================
PROFILE="${PROFILE:-$(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo devops)}"
print_section "Profile: ${PROFILE}"

# Установка Nix (--no-channel-add: каналы не нужны — пакеты едут по flake.lock,
# а дефолтный nixpkgs-unstable канал тянет ~400MB незапиненного дерева)
if ! command -v nix &> /dev/null; then
  print_section "Installing Nix"
  curl -L https://nixos.org/nix/install | sh -s -- --no-channel-add
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# Flakes нужны для home-manager; ванильный nix не включает их по умолчанию
mkdir -p "$HOME/.config/nix"
if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
fi

# Bridge-симлинки: home-модули (files.nix/hooks.nix) ссылаются на ~/dotfiles,
# конфиги исторически — на ~/.dotfiles. Оба пути должны вести в один клон.
# DevPod клонирует в ~/dotfiles (clone-path не настраивается), руками часто ~/.dotfiles
[[ "$DOTFILES_ROOT" != "$HOME/.dotfiles" && ! -e "$HOME/.dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/.dotfiles"
[[ "$DOTFILES_ROOT" != "$HOME/dotfiles" && ! -e "$HOME/dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/dotfiles"

# Сабмодуль private — ДО switch: на него ссылаются симлинки из home-модулей
# (ssh-конфиги контуров, .config/git-identities), и без содержимого они висячие.
# Только private, не --recursive: assets в контейнере не нужен.
#
# ЖЁСТКИЙ отказ, а не warn. Отсутствие сабмодуля не ломает установку заметно —
# оно ломает её тихо: симлинк на месте, файла нет, git молча пропускает
# несуществующий include, и рабочий репозиторий получает ЛИЧНУЮ почту вместо
# kvt@ вместе с подписью не тем ключом. Замечается это уже по невалидным
# коммитам в истории, когда чинить дорого. Поэтому лучше не подняться совсем.
# Проверяется не только код возврата, но и реальный файл: `submodule update`
# отдаёт 0 и на пустом каталоге, если сабмодуль зарегистрирован, но не выкачан.
# Shallow first, full clone on failure. Nothing here reads a submodule's
# history, but `--depth 1` fetches only the branch tip: the moment the submodule
# gains a commit while the superproject still pins the previous one, the pinned
# commit is missing from the shallow fetch and the checkout fails. That is the
# normal state between pointer bumps, not a fault, so the fallback is required.
submodule_init() {
  git -C "$DOTFILES_ROOT" submodule update --init --depth 1 "$1" 2>/dev/null \
    || git -C "$DOTFILES_ROOT" submodule update --init "$1"
}

print_section "Initializing private submodule"
if ! submodule_init private \
   || [[ ! -f "$DOTFILES_ROOT/private/git/includes.conf" ]]; then
  echo "✖ FATAL: сабмодуль private не подтянулся." >&2
  echo "  Без него git подставит личную идентичность в рабочих репозиториях" >&2
  echo "  и подпишет коммиты не тем ключом — молча." >&2
  echo "  Причина обычно одна: в контейнер не проброшен ssh-агент с ключом к" >&2
  echo "  github.com (см. IdentityAgent в блоке Host *.devpod на хосте)." >&2
  exit 1
fi

# ===============================
# Весь user-space одним switch: пакеты + симлинки + activation-хуки
# (claude, ccusage, zinit, nvim-плагины, MCP). Версии пиннятся flake.lock.
# Атрибут: <user>-<profile>-<arch>, см. platform/nix/flake.nix
# ===============================
FLAKE_DIR="$DOTFILES_ROOT/platform/nix"
HM_CONFIG="$(whoami)-${PROFILE}-$(uname -m)-linux"

# Generation marker: the prebuilt image bakes the home-manager generation and
# stamps ~/.dotfiles-generation with a hash of everything that generation was
# built from. When the clone hashes to the same value, the baked generation is
# already exactly what a switch would produce (out-of-store symlinks resolve
# through ~/dotfiles, so they start pointing into the fresh clone by
# themselves) — and the switch is skipped entirely. That saves the flake eval
# plus every activation hook (Lazy! sync, treesitter, mason, MCP) on the hot
# path of devpod up. Freshness is NOT this script's job: updl and the nightly
# devpod-update.sh still switch unconditionally.
#
# The hash must be computed identically here and in platform/linux/Dockerfile.
# darwin-only files are excluded to mirror the CI rebuild triggers
# (.github/workflows/devcontainer-image.yml): they never affect the Linux
# generation, but a mac-only commit would otherwise flip the hash without a
# rebuilt image and force a pointless full switch until the next weekly build.
#
# LC_ALL=C on both sides: `sort` collates by locale, and this very file set
# already orders differently between C and en_US.UTF-8 (tools/nvim/.stylua.toml
# moves from position 10 to 47). Ambient locale agreeing between the build and
# every runtime invocation is not something to rely on — an ssh client sending
# LC_* is enough to break it, and the only symptom would be the skip quietly
# never firing.
#
# lazy-lock.json is excluded because it is NOT part of the source tree: it is
# gitignored, absent from a fresh clone, and written by `Lazy! sync` — inside the
# image while it builds, and inside a workspace on the first nightly updl. Left
# in, the hash would describe two different trees on the two sides and the skip
# would silently never fire (verified: 6326fc7b… in the image against 0d7daed3…
# for the same commit freshly cloned).
generation_hash() {
  (cd "$DOTFILES_ROOT" \
    && find platform/nix tools/nvim -type f \
         ! -path platform/nix/darwin-configuration.nix \
         ! -path platform/nix/home/darwin.nix \
         ! -name lazy-lock.json -print0 \
       | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}
GEN_FILE="$HOME/.dotfiles-generation"
CURRENT_GEN="$(generation_hash)"
# The marker only vouches for the profile the image itself baked: rolling
# PROFILE=devops onto a :core image must still go through a full switch.
BAKED_PROFILE="$(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo none)"

if [[ -f "$GEN_FILE" && "$CURRENT_GEN" == "$(cat "$GEN_FILE")" && "$PROFILE" == "$BAKED_PROFILE" ]]; then
  print_section "Prebuilt generation matches — skipping home-manager switch"
  # The one thing the skipped activation hooks still owe us (installClaudeCustom
  # in home/hooks.nix): the custom submodule. It cannot live in a public image,
  # so it is cloned here — shallow, we only ever read its working tree.
  # Soft-fail like the hook: a missing ssh key must not break the whole setup.
  # Нужен ли он СЕЙЧАС, решает сверка ниже: если образ запечён под тот же
  # коммит сабмодуля, установщик не побежит, и содержимое понадобится только
  # когда пользователь запустит claude — то есть заметно позже. Тогда клон
  # уходит в фон и не стоит трёх секунд на горячем пути. Гонки нет: git-операций
  # после этой точки в скрипте не остаётся.
  BAKED_CUSTOM="$(cat "$HOME/.claude/.mcp-baked-from" 2>/dev/null || echo none)"
  PINNED_CUSTOM="$(git -C "$DOTFILES_ROOT" ls-tree HEAD tools/claude/custom | awk '{print $3}')"

  if [[ ! -f "$DOTFILES_ROOT/tools/claude/custom/install.sh" ]]; then
    if [[ "$BAKED_CUSTOM" == "$PINNED_CUSTOM" ]]; then
      submodule_init tools/claude/custom >/dev/null 2>&1 &
      disown
    else
      submodule_init tools/claude/custom \
        || echo "warn: claude custom submodule skipped (нет ssh-агента или ключа)"
    fi
  fi
  # Its installer is only needed when the image did not already bake its result:
  # ~/.claude/* symlinks and the MCP registrations in ~/.claude.json both live in
  # $HOME, which the image carries. Running it anyway cost 6s of the 12s this
  # branch used to take — 3s of `uv sync` for the timing project (which on Linux
  # is reached over http and needs no local venv at all) and 3s of respawning
  # `claude` twice per server.
  #
  # What the image baked is only valid for the submodule commit it was built
  # against, and that commit is in neither the generation hash nor the CI rebuild
  # triggers — so a changed MCP roster (a new server, or the timing address fix
  # we already had once) would never reach a new container while the marker
  # matched. Hence the comparison against the pinned commit rather than a probe
  # for one server name: it also self-heals, because a stale image simply fails
  # the comparison and the installer runs. (Both values are read above, where
  # they also decide whether the submodule is needed synchronously at all.)
  if [[ -f "$DOTFILES_ROOT/tools/claude/custom/install.sh" ]] \
     && [[ "$BAKED_CUSTOM" != "$PINNED_CUSTOM" || ! -L "$HOME/.claude/skills" ]]; then
    PATH="$HOME/.local/bin:$PATH" "$DOTFILES_ROOT/tools/claude/custom/install.sh" \
      || echo "warn: MCP install failed"
  fi
else
  print_section "Activating home-manager configuration: ${HM_CONFIG}"
  # В пребилт-образе home-manager уже в профиле (programs.home-manager.enable), и
  # CLI — тонкая обёртка: он строит "<flake>#…activationPackage", то есть модули и
  # пакеты приезжают из flake.lock, а не из бинаря. А `nix run` пересобирал бы сам
  # пакет home-manager со всем замыканием (nix, nixos-option, man-db) — его вымел
  # nix-collect-garbage при сборке образа (Dockerfile:99,110), поэтому оно качалось
  # заново на КАЖДЫЙ devpod up: 106 путей, 66.8 MiB, ~50 секунд.
  # Голый образ без профиля уходит в else — там `nix run` единственный способ.
  # --inputs-from: home-manager резолвится по flake.lock репо, а не по свежему master;
  # -b: файлы, которые HM отказался бы перезаписать, уезжают в *.hm-backup
  if command -v home-manager &> /dev/null; then
    home-manager switch --flake "$FLAKE_DIR#${HM_CONFIG}" -b hm-backup
  else
    nix run --inputs-from "$FLAKE_DIR" home-manager -- switch --flake "$FLAKE_DIR#${HM_CONFIG}" -b hm-backup
  fi
  echo "$CURRENT_GEN" > "$GEN_FILE"
fi

# Маркер профиля — читает cron-обновление (automation/cron/devpod-update.sh)
echo "$PROFILE" > "$HOME/.dotfiles-profile"

# ===============================
# System-уровень (sudo): вне зоны home-manager. В prebuilt-образе уже сделано —
# эти шаги идемпотентны и отрабатывают мгновенно
# ===============================
print_section "Setting default shell to zsh"
ZSH_PATH="$(command -v zsh)"
# Сравнивать надо с ФАКТИЧЕСКИМ шеллом из passwd, а не с $SHELL: в сессии,
# запущенной уже под zsh, $SHELL показывает zsh, хотя в passwd остался bash —
# и блок молча пропускался.
CURRENT_SHELL="$(getent passwd "$(whoami)" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
  # -qx, а не -q: без точного совпадения строки запись дублировалась при каждом
  # прогоне (в /etc/shells накопилось два одинаковых /usr/bin/zsh).
  grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null \
    || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  # Сразу через sudo: обычный chsh спрашивает пароль через PAM, а у пользователя
  # контейнера пароля нет — «chsh: PAM: Authentication failure». Раньше первый
  # вызов падал именно так, а результат гасился `2>/dev/null || true`, из-за чего
  # шелл тихо оставался bash после каждого пересоздания контейнера.
  sudo chsh -s "$ZSH_PATH" "$(whoami)" \
    || echo "warn: не удалось сменить шелл на zsh — останется $CURRENT_SHELL"
fi

# Timezone: containers default to UTC — set local zone so tmux clock, date and
# logs show correct time. Override with CONTAINER_TZ at create time if needed.
CONTAINER_TZ="${CONTAINER_TZ:-Europe/Moscow}"
if [[ -f "/usr/share/zoneinfo/$CONTAINER_TZ" ]]; then
  print_section "Setting timezone to ${CONTAINER_TZ}"
  sudo ln -sf "/usr/share/zoneinfo/$CONTAINER_TZ" /etc/localtime
  echo "$CONTAINER_TZ" | sudo tee /etc/timezone >/dev/null
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"
