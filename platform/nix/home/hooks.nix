{ config, lib, pkgs, ... }:
let
  dotfiles = "${config.home.homeDirectory}/${if pkgs.stdenv.isDarwin then ".dotfiles" else "dotfiles"}";
  # Активация может бежать при сборке образа (сети/клона может не быть) и при
  # каждом switch — каждый хук идемпотентен и толерантен к оффлайну
  after = lib.hm.dag.entryAfter [ "linkGeneration" ];
in {
  home.activation = {
    # Claude Code — сознательно НЕ через nix: официальный бинарь самообновляется,
    # в иммутабельном store это невозможно. Хук лишь ставит его при отсутствии
    # PATH: скачанные инсталлеры зовут curl/tar по имени, а PATH активации минимальный
    installClaudeCode = after ''
      if [ ! -x "$HOME/.local/bin/claude" ] && ! command -v claude >/dev/null 2>&1; then
        run ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
          && PATH="${lib.makeBinPath [ pkgs.curl pkgs.coreutils pkgs.gnutar pkgs.gzip pkgs.unzip ]}:$PATH" \
             run ${pkgs.bash}/bin/bash /tmp/claude-install.sh \
          && run rm -f /tmp/claude-install.sh \
          || echo "warn: claude install skipped (offline?)"
      fi
    '';

    # ccusage не в nixpkgs (только npm) — прямой бинарь в ~/.local, чтобы
    # statusline.sh не поднимал npx на каждый рендер
    installCcusage = after ''
      if [ ! -x "$HOME/.local/bin/ccusage" ] && ! command -v ccusage >/dev/null 2>&1; then
        run ${pkgs.nodejs_24}/bin/npm install -g --prefix "$HOME/.local" ccusage \
          || echo "warn: ccusage install skipped (offline?)"
      fi
    '';

    installTpm = after ''
      if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        run ${pkgs.git}/bin/git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" \
          || echo "warn: tpm clone skipped (offline?)"
      fi
    '';

    # PATH: инсталлер zinit клонирует репо через git по имени
    installZinit = after ''
      if [ ! -d "$HOME/.local/share/zinit" ]; then
        run ${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh -o /tmp/zinit-install.sh \
          && PATH="${lib.makeBinPath [ pkgs.git pkgs.curl pkgs.coreutils ]}:$PATH" NO_INPUT=1 \
             run ${pkgs.bash}/bin/bash /tmp/zinit-install.sh \
          && run rm -f /tmp/zinit-install.sh \
          || echo "warn: zinit install skipped (offline?)"
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
            || echo "warn: schema $rel not cached (yamlls falls back to URL)"
        fi
      done
    '';

    # nvim-плагины: только при живом конфиге (при сборке образа симлинк на
    # ~/dotfiles ещё висячий) и пустом каталоге плагинов. nvim из pkgs:
    # на darwin он в системном профиле, а не в ~/.nix-profile
    syncNvimPlugins = after ''
      if [ -e "$HOME/.config/nvim/init.lua" ] && [ ! -d "$HOME/.local/share/nvim/lazy" ]; then
        PATH="$HOME/.nix-profile/bin:${lib.makeBinPath [ pkgs.git pkgs.neovim ]}:$PATH" \
          run nvim --headless "+Lazy! sync" +qa \
          || echo "warn: nvim Lazy sync failed (offline?)"
      fi
    '';

    # Приватный submodule (ssh) + установка MCP-серверов; без ключей — мягкий skip
    installClaudeCustom = after ''
      if [ -d "${dotfiles}/.git" ]; then
        if [ ! -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          run ${pkgs.git}/bin/git -C "${dotfiles}" submodule update --init tools/claude/custom \
            || echo "warn: claude custom submodule skipped (no ssh key?)"
        fi
        if [ -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          run "${dotfiles}/tools/claude/custom/install.sh" \
            || echo "warn: MCP install failed"
        fi
      fi
    '';
  };
}
