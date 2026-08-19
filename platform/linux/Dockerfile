# Prebuilt devcontainer-образ для DevPod: Ubuntu + Nix + home-manager.
# Собирается в CI (.github/workflows/devcontainer-image.yml) под amd64+arm64,
# публикуется как ghcr.io/cosmdandy/devcontainer:{core,devops}. Store-пути
# совпадают с flake.lock репо, поэтому home-manager switch при devpod up —
# мгновенный no-op.
#
# Профиль выбирается стадией, а не build-arg: `--target core` / `--target devops`.
# Смысл в том, что devops наследует стадию core, поэтому нижние слои у двух
# образов буквально одни и те же — реестр их дедуплицирует, а имея :core,
# клиент дотягивает :devops одной дельтой. Заодно монолитный слой на ~1.2 ГБ
# разбивается надвое, что даёт параллельную загрузку.
#
# ВАЖНО: nix-collect-garbage обязан оставаться в ТОМ ЖЕ RUN, что и switch.
# Удаление отдельным слоем не освобождает место — файлы остаются в нижнем слое
# под whiteout'ом (проверено: 68 MiB против 8 MiB на синтетике), и build-
# зависимости вроде Go-тулчейна terraform запеклись бы в образ навсегда.

# ubuntu-24.04 (пин по digest мульти-арх индекса)
FROM mcr.microsoft.com/devcontainers/base@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae AS base

ENV TZ=Europe/Moscow \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Пользователя приносит базовый образ Microsoft — он там vscode с uid 1000.
# Именно ПЕРЕИМЕНОВАНИЕ, а не создание нового: на uid 1000 завязаны права
# bind-mount'ов devpod, а новый пользователь получил бы 1001. Делается первым
# делом в стадии, пока под ним никто не залогинен (usermod -m переносит
# домашний каталог) и до любого USER.
#
# uid обязан остаться 1000: devpod создаёт каталог воркспейса на хосте с uid
# пользователя контейнера, и все существующие воркспейсы лежат под 1000.
# Расхождение uid контейнера с хостом devpod чинит сам — рекурсивным chown по
# домашнему каталогу, и это НЕ дешёвая операция: 1.5 ГБ / 54847 файлов поверх
# overlay2 с metacopy=false копируются целиком (замерено на kvt-d-01: 8.5 минут
# и сломанный /nix в результате). Отключено через updateRemoteUserUID в
# .devcontainer/devcontainer.json — см. комментарий там.
#
# Правило sudo лежит отдельным файлом /etc/sudoers.d/vscode со строкой
# `vscode ALL=(root) NOPASSWD:ALL` (его пишет фича common-utils), и usermod за
# ним НЕ следует: без правки sudo у cosmdandy просто нет, а на него опирается
# .devcontainer/setup.sh на голом образе. Проверено в контейнере: uid/gid
# остаются 1000, `sudo -n id` после правки отвечает uid=0, visudo -c — OK.
#
# Системная часть — то же, что .devcontainer/setup.sh делает на голом образе
RUN usermod -l cosmdandy -d /home/cosmdandy -m vscode \
  && groupmod -n cosmdandy vscode \
  && sed -i 's/^vscode /cosmdandy /' /etc/sudoers.d/vscode \
  && mv /etc/sudoers.d/vscode /etc/sudoers.d/cosmdandy \
  && apt-get update \
  && apt-get install -y --no-install-recommends zsh python3-pip python3-venv locales \
  && rm -rf /var/lib/apt/lists/* \
  && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  && ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime \
  && echo "$TZ" > /etc/timezone \
  && chsh -s /usr/bin/zsh cosmdandy \
  # Тот же PATH, что и в ENV ниже, но на уровне zsh. Дублирование намеренное:
  # lifecycle-хуки из devcontainer.json (postCreateCommand и соседи) devpod
  # запускает через su, а тот сбрасывает окружение на системный дефолт — ENV
  # образа теряется вместе с ~/.nix-profile/bin. Восстановить его в этот момент
  # некому: ~/.zprofile от home-manager ведёт в ~/dotfiles, а тот снимается
  # ниже и появляется заново только при клонировании dotfiles, то есть уже
  # ПОСЛЕ хуков. /etc/zsh/zshenv читает любой zsh, включая `zsh -c`, и на
  # висячие симлинки в $HOME не смотрит. Без этого `postCreateCommand: npm ci`
  # падает с exit 127, хотя npm в образе есть.
  && printf '%s\n' \
       'if [[ -d "$HOME/.nix-profile/bin" && ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]]; then' \
       '  export PATH="$HOME/.nix-profile/bin:$PATH"' \
       'fi' >> /etc/zsh/zshenv \
  && mkdir -m 0755 /nix && chown cosmdandy:cosmdandy /nix \
  # маркер для .devcontainer/setup.sh: системная подготовка уже в образе,
  # повторять её при каждом создании воркспейса незачем
  && echo prebuilt > /etc/devcontainer-prebuilt

USER cosmdandy
ENV USER=cosmdandy \
    HOME=/home/cosmdandy
WORKDIR /home/cosmdandy

# Лейбл devcontainer.metadata приезжает из базового образа со значением
# […, {"remoteUser":"vscode"}], и devcontainers читает ЕГО, а не директиву USER
# выше. В .devcontainer/devcontainer.json этого репозитория remoteUser задан
# явно, но рабочие репозитории получают образ через --devcontainer-image
# (private/zsh/work-stack.sh) и своего remoteUser не задают — проверено на
# kvt-d-01: во всех восьми воркспейсах его нет. Для них единственный источник
# правды — этот лейбл, иначе devpod up после переименования просит
# несуществующего vscode.
#
# Значение перезаписывается целиком (LABEL не умеет дополнять): из него выпадают
# id'шники фич common-utils и git. Это безразлично — ни один наш devcontainer.json
# фичи не запрашивает, они и так запечены в базовый образ.
LABEL devcontainer.metadata='[{"remoteUser":"cosmdandy"}]'

# Nix single-user: версия запинена, скрипт сверяется с checksum (security.md);
# --no-channel-add — канал не нужен (всё флейковое) и иначе запёк бы ~400MB
# незапиненного nixpkgs-unstable в образ мимо nix-collect-garbage
RUN curl -fsSL https://releases.nixos.org/nix/nix-2.33.1/install -o /tmp/nix-install \
  && echo "2bbe0d388d1bee5ee60ed67b844f428b6031a1b7c42d7d03319ad7133867290d  /tmp/nix-install" | sha256sum -c - \
  && sh /tmp/nix-install --no-daemon --no-channel-add \
  && rm /tmp/nix-install \
  && mkdir -p "$HOME/.config/nix" \
  && echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"

ENV PATH=/home/cosmdandy/.nix-profile/bin:$PATH

COPY --chown=cosmdandy:cosmdandy platform/nix /opt/dotfiles/platform/nix

# Конфиг nvim нужен хукам: home-manager линкует ~/.config/nvim ->
# ~/dotfiles/tools/nvim (mkOutOfStoreSymlink), и без него симлинк висячий,
# guard `-e ~/.config/nvim/init.lua` не проходит, а syncNvimPlugins/
# installMasonTools молча пропускаются — плагины и mason качались в КАЖДЫЙ
# воркспейс (1.2 ГБ).
#
# Лежит в /opt, а НЕ в ~/dotfiles: туда devpod клонирует настоящий репозиторий,
# непустой каталог сломал бы клон. На время активации каждая стадия вешает
# симлинк ~/dotfiles -> /opt/dotfiles и снимает его в том же RUN — снятие
# мгновенное и следа в слое не оставляет.
#
# Симлинк обязан создаваться в КАЖДОЙ стадии: devops собирается поверх core, и
# пока core сносил каталог насовсем, devops оставался с висячим симлинком и
# пропускал mason — из-за чего jsonnet-language-server (ему нужен go, а он
# только в devops-профиле) не попадал в образ вообще никогда.
COPY --chown=cosmdandy:cosmdandy tools/nvim /opt/dotfiles/tools/nvim

# .zshrc нужен по той же причине: zinit при первом старте оболочки клонирует
# пять плагинов (~13 МБ) — это происходило в каждом воркспейсе и было видно
# пользователю как пауза с прогресс-барами. Достаточно один раз запустить
# интерактивный zsh при сборке: плагины объявлены с `wait lucid`, то есть
# асинхронно, но планировщик успевает отработать до выхода (проверено).
COPY --chown=cosmdandy:cosmdandy tools/zsh /opt/dotfiles/tools/zsh

# Generation marker: hash of the source tree the baked home-manager generation
# is built from. platform/linux/install.sh computes the same hash over the fresh
# clone and, on a match, skips the switch and every activation hook — that is
# what makes devpod up on a current image take seconds instead of a minute and a
# half. MUST stay byte-identical with generation_hash() there; the darwin
# exclusions mirror the CI rebuild triggers, and lazy-lock.json is out because it
# is gitignored and therefore absent from a clone.
#
# Stamped HERE, in the pristine tree straight after the COPY, and not next to the
# switch below: `Lazy! sync` writes lazy-lock.json into tools/nvim while the core
# stage runs, so a hash taken afterwards described a tree no clone can reproduce
# — the marker never matched and the skip silently did nothing.
RUN (cd /opt/dotfiles && find platform/nix tools/nvim -type f \
       ! -path platform/nix/darwin-configuration.nix \
       ! -path platform/nix/home/darwin.nix \
       ! -name lazy-lock.json -print0 \
     | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1) \
    > "$HOME/.dotfiles-generation"

# --- core: редактор, шелл, git, CI ---
# ~/.dotfiles-profile — тот же файл, что пишет platform/linux/install.sh и
# читают updl с devpod-update.sh: запечённый в образ, он даёт рабочий updl
# сразу, ещё до первого запуска install.sh
FROM base AS core
# Коммит сабмодуля tools/claude/custom, под который запечён набор MCP ниже.
# Его пишет CI (.github/workflows/devcontainer-image.yml), а install.sh сверяет
# с указателем в клоне: разошлись — значит набор в сабмодуле менялся после
# сборки образа, и установщик сабмодуля надо всё-таки прогнать. Без этой сверки
# новый сервер (или, как было, исправленный адрес timing) не доехал бы до
# контейнеров до самой ближайшей пересборки образа, молча.
# unknown — на случай сборки руками: тогда сверка не сойдётся и установщик
# отработает, то есть ошибка в безопасную сторону.
ARG CUSTOM_SHA=unknown
RUN ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#cosmdandy-core-$(uname -m)-linux" -b hm-backup \
  # плагины zinit: только в core, devops наследует их вместе со слоем.
  # || true — оболочка может вернуть ненулевой код из-за мелочей вроде
  # отсутствующего TERM, но плагины к этому моменту уже склонированы
  && (zsh -i -c exit >/dev/null 2>&1 || true) \
  # MCP servers, baked whole: the binaries AND their registration in
  # ~/.claude.json, which lives in $HOME and therefore ships with the image.
  # platform/linux/install.sh checks exactly this end state and skips the
  # submodule's installer when it holds — worth 6 s of every devpod up (3 s of
  # `uv sync` for the timing project, which on Linux is reached over http and
  # needs no local venv, plus 3 s of respawning `claude` twice per server).
  # The submodule itself cannot be baked (private repo, public image); its
  # ~/.claude/* symlinks can, and are — they dangle until the workspace clones
  # it, which is legal and resolves by itself.
  # Paths are absolute: ENV PATH here has no ~/.local/bin (zshrc adds it).
  # The timing url must match the one in tools/claude/custom/install.sh.
  && uv tool install mcp-atlassian \
  && npm install -g --prefix "$HOME/.npm-global" @upstash/context7-mcp \
  && "$HOME/.local/bin/claude" mcp add -s user atlassian -- "$HOME/.local/bin/mcp-atlassian" \
  && "$HOME/.local/bin/claude" mcp add -s user context7 -- "$HOME/.npm-global/bin/context7-mcp" \
  && "$HOME/.local/bin/claude" mcp add -s user -t http timing "http://100.64.0.1:7233/mcp" \
  # rm before ln, and assert afterwards: `ln -sfn` onto a destination that is a
  # REAL directory neither replaces it nor fails — -n only guards a symlink to a
  # directory, so ln follows the real one and quietly creates the link INSIDE it,
  # exit 0. None of the six exist as directories at this point today, but the
  # floating `claude` binary runs twice just above and could start creating one;
  # the failure would ship as ~/.claude/<d> being a real directory, and only
  # `skills` is checked at runtime — the rest would be silently absent from every
  # workspace, with both the build and install.sh green.
  && for d in skills agents commands rules labs output-styles; do \
       rm -rf "$HOME/.claude/$d" \
       && ln -s "$HOME/dotfiles/tools/claude/custom/$d" "$HOME/.claude/$d" \
       && [ -L "$HOME/.claude/$d" ] || exit 1; \
     done \
  && echo "$CUSTOM_SHA" > "$HOME/.claude/.mcp-baked-from" \
  && rm -f "$HOME/dotfiles" \
  # кэши сборки mason (npm ~71 МБ, go ~66 МБ, pip ~121 МБ) — мусор, сами пакеты
  # уже в ~/.local/share/nvim/mason; в том же RUN, иначе останутся под whiteout.
  # pip кэширует колёса venv'ов (mypy, yamllint, ansible-lint, debugpy) и по
  # объёму крупнее двух других вместе взятых. ~/.cache/uv — колёса mcp-atlassian.
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
            "$HOME/.cache/pip" "$HOME/.cache/uv" \
  && nix-collect-garbage -d \
  && echo core > "$HOME/.dotfiles-profile"

# --- devops: core + IaC/K8s/container ---
# Наследует core целиком, поэтому в слой ложится только дельта пакетов
FROM core AS devops
RUN ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#cosmdandy-devops-$(uname -m)-linux" -b hm-backup \
  # Прогрев повторяется и здесь, хотя плагины zinit уже приехали из core.
  # Причина другая: completion'ы генерируются блоком в .zshrc при первом старте
  # шелла, а профиль devops приносит kubectl, helm, talosctl и k9s — которых в
  # core не было. Без этой строки их completion'ы генерировались в первом же
  # шелле каждого нового воркспейса (замер в контейнере: 39+50+43+74 мс) и
  # вдобавок не попадали в запечённый .zcompdump. Строка ДОЛЖНА идти после
  # home-manager switch: до него новых бинарей ещё нет.
  && (zsh -i -c exit >/dev/null 2>&1 || true) \
  && rm -f "$HOME/dotfiles" \
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
            "$HOME/.cache/pip" \
  && nix-collect-garbage -d \
  && echo devops > "$HOME/.dotfiles-profile"
