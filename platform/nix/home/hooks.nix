{ config, lib, pkgs, ... }:
let
  dotfiles = "${config.home.homeDirectory}/${if pkgs.stdenv.isDarwin then ".dotfiles" else "dotfiles"}";
  # Активация может бежать при сборке образа (сети/клона может не быть) и при
  # каждом switch — каждый хук идемпотентен и толерантен к оффлайну
  after = lib.hm.dag.entryAfter [ "linkGeneration" ];
  # installPackages в списке обязателен: он ставит пакеты профиля и идёт ПОСЛЕ
  # обычных after-хуков. Без него mason бежал бы, пока ~/.nix-profile указывает
  # на прежнее поколение, и на стадии devops не нашёл бы go — из-за чего
  # jsonnet-language-server молча не ставился (проверено на собранном образе).
  afterNvim = lib.hm.dag.entryAfter [ "syncNvimPlugins" "installPackages" ];

  # Хуки намеренно не валят активацию при офлайне — иначе сборка образа и
  # devpod up ломались бы от любой сетевой заминки. Но из-за этого неудачная
  # установка выглядела как успешная: одинокий "warn:" тонул в сотнях строк
  # вывода, и узнать о пропаже можно было только открыв nvim. Поэтому каждый
  # warn дополнительно копится в файле, а последним шагом печатается сводка.
  # Файл, а не переменная: не зависит от того, выполняются ли записи DAG в
  # одном шелле, и остаётся доступным после активации для разбора.
  warnFile = "${config.home.homeDirectory}/.cache/home-manager-warnings";
  warn = msg: ''{ echo "warn: ${msg}"; echo "${msg}" >> "${warnFile}"; }'';
in {
  home.activation = {
    # Обнуляем накопитель до первого хука, иначе сводка показывала бы warn'ы
    # прошлой активации. entryBefore linkGeneration — раньше всех наших.
    initWarnings = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      run mkdir -p "$(dirname "${warnFile}")"
      run rm -f "${warnFile}"
    '';

    # Claude Code — сознательно НЕ через nix: официальный бинарь самообновляется,
    # в иммутабельном store это невозможно. Хук лишь ставит его при отсутствии
    # PATH: скачанные инсталлеры зовут curl/tar по имени, а PATH активации минимальный
    # :/usr/bin:/bin в хвосте — PATH активации не содержит системных путей,
    # а инсталлер на macOS зовёт shasum (перловый скрипт из /usr/bin)
    installClaudeCode = after ''
      if [ ! -x "$HOME/.local/bin/claude" ] && ! command -v claude >/dev/null 2>&1; then
        run ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
          && PATH="${lib.makeBinPath [ pkgs.curl pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.unzip ]}:$PATH:/usr/bin:/bin" \
             run ${pkgs.bash}/bin/bash /tmp/claude-install.sh \
          && run rm -f /tmp/claude-install.sh \
          || ${warn "claude install skipped (offline?)"}
      fi
    '';

    installTpm = after ''
      if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        run ${pkgs.git}/bin/git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
          || ${warn "tpm clone skipped (offline?)"}
      fi
    '';

    # PATH: инсталлер zinit клонирует репо через git по имени.
    # ZSHRC=/dev/null: иначе инсталлер дописывает annex-блок и маркер сквозь
    # симлинк ~/.zshrc прямо в репо — наш .zshrc уже содержит zinit-блок
    installZinit = after ''
      if [ ! -d "$HOME/.local/share/zinit" ]; then
        run ${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh -o /tmp/zinit-install.sh \
          && PATH="${lib.makeBinPath [ pkgs.git pkgs.curl pkgs.coreutils ]}:$PATH" NO_INPUT=1 ZSHRC=/dev/null \
             run ${pkgs.bash}/bin/bash /tmp/zinit-install.sh \
          && run rm -f /tmp/zinit-install.sh \
          || ${warn "zinit install skipped (offline?)"}
      fi
    '';

    # CRD JSON-схемы для yamlls кэшируем локально (оффлайн + нет сетевого лага
    # на первом открытии). yamlls.lua сам берёт file://-кэш, иначе фолбэк на URL
    cacheYamlSchemas = after ''
      SCHEMA_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/yaml-schemas"
      CRD_BASE="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main"
      for rel in \
        argoproj.io/application_v1alpha1.json \
        gateway.networking.k8s.io/gateway_v1.json \
        gateway.networking.k8s.io/gatewayclass_v1.json \
        gateway.networking.k8s.io/httproute_v1.json \
        gateway.networking.k8s.io/referencegrant_v1beta1.json; do
        if [ ! -f "$SCHEMA_DIR/$rel" ]; then
          run mkdir -p "$SCHEMA_DIR/$(dirname "$rel")"
          run ${pkgs.curl}/bin/curl -fsSL "$CRD_BASE/$rel" -o "$SCHEMA_DIR/$rel" \
            || { m="schema $rel not cached (yamlls falls back to URL)"; \
                 echo "warn: $m"; echo "$m" >> "${warnFile}"; }
        fi
      done
    '';

    # nvim-плагины: только при живом конфиге (без него симлинк ~/.config/nvim
    # висячий — так отсекается сборка образа до COPY tools/nvim).
    # Guard'а по каталогу lazy НЕТ: Lazy! sync — это install + clean + update,
    # он идемпотентен и должен идти на каждой активации, иначе добавленный в
    # конфиг плагин не приезжал бы по updl/updm (каталог-то уже есть).
    # Плагины сознательно не пинятся: lazy-lock.json в .gitignore, в контекст
    # сборки не попадает, версии всегда свежие — как zinit update в updl.
    # nvim из pkgs: на darwin он в системном профиле, а не в ~/.nix-profile.
    # curl/tar — nvim-treesitter качает парсеры; /usr/bin — cc для их сборки
    syncNvimPlugins = after ''
      if [ -e "$HOME/.config/nvim/init.lua" ]; then
        PATH="$HOME/.nix-profile/bin:${lib.makeBinPath [ pkgs.git pkgs.neovim pkgs.curl pkgs.gnutar pkgs.gzip pkgs.tree-sitter ]}:$PATH:/usr/bin:/bin" \
          run nvim --headless "+Lazy! sync" +qa \
          || ${warn "nvim Lazy sync failed (offline?)"}
      fi
    '';

    # Mason-пакеты (LSP-серверы, линтеры, форматтеры из ensure_installed).
    # Отдельным шагом после Lazy sync: mason-tool-installer подключён как
    # зависимость nvim-lspconfig, а тот грузится по BufReadPre/BufNewFile —
    # в headless без открытого файла событие не наступает, setup() не бежит и
    # run_on_start молчит. Отсюда явный Lazy! load + Sync-вариант команды
    # (обычный MasonToolsInstall асинхронный, nvim вышел бы раньше установки).
    # Guard'а по каталогу mason НЕТ намеренно: сама команда идемпотентна и при
    # полном комплекте отрабатывает за 0с (замерено), а «пропускать, если что-то
    # уже стоит» ломало бы многостадийный образ — стадия devops унаследовала бы
    # непустой mason/ от core и не доставила бы jsonnet-language-server, которому
    # нужен go (он есть только в devops-профиле). Без guard'а недостающее
    # доустанавливается на любом switch, где инструмент наконец доступен.
    # PATH: инсталлеры mason тянут пакеты через npm/pip/luarocks и распаковывают;
    # ~/.nix-profile/bin первым — оттуда берётся go на devops-профиле
    installMasonTools = afterNvim ''
      if [ -e "$HOME/.config/nvim/init.lua" ]; then
        PATH="$HOME/.nix-profile/bin:${lib.makeBinPath [ pkgs.git pkgs.neovim pkgs.curl pkgs.gnutar pkgs.gzip pkgs.unzip pkgs.nodejs_24 pkgs.python313 pkgs.luarocks pkgs.uv ]}:$PATH:/usr/bin:/bin" \
          run nvim --headless "+Lazy! load nvim-lspconfig" "+MasonToolsInstallSync" +qa \
          || ${warn "mason tools install failed (offline?)"}
      fi
    '';

    # Приватный submodule (ssh) + установка MCP-серверов; без ключей — мягкий skip.
    # PATH: install.sh зовёт claude (в ~/.local/bin), uv (deps MCP-серверов)
    installClaudeCustom = after ''
      if [ -d "${dotfiles}/.git" ]; then
        if [ ! -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          PATH="${lib.makeBinPath [ pkgs.git pkgs.openssh ]}:$PATH:/usr/bin:/bin" \
            run ${pkgs.git}/bin/git -C "${dotfiles}" submodule update --init tools/claude/custom \
            || ${warn "claude custom submodule skipped (нет ssh-агента или ключа)"}
        fi
        if [ -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          PATH="$HOME/.local/bin:${lib.makeBinPath [ pkgs.git pkgs.uv ]}:$PATH:/usr/bin:/bin" \
            run "${dotfiles}/tools/claude/custom/install.sh" \
            || ${warn "MCP install failed"}
        fi
      fi
    '';

    # Сводка последним шагом: активация всё равно завершается успешно (это
    # осознанно — офлайн не должен её валить), но теперь пропуски видно сразу,
    # а не при первом запуске nvim через неделю.
    reportWarnings = lib.hm.dag.entryAfter [
      "installClaudeCode" "installTpm" "installZinit" "cacheYamlSchemas"
      "syncNvimPlugins" "installMasonTools" "installClaudeCustom"
    ] ''
      if [ -s "${warnFile}" ]; then
        echo ""
        echo "  ВНИМАНИЕ: активация прошла, но $(wc -l < "${warnFile}" | tr -d ' ') шаг(ов) пропущено:"
        sed 's/^/    - /' "${warnFile}"
        echo "  подробности: ${warnFile}"
        echo ""
      fi
    '';
  };
}
