{ config, lib, pkgs, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  after = lib.hm.dag.entryAfter [ "linkGeneration" ];
  # PATH активации минимальный: brew-бинари (devpod, orb) ищем явно,
  # grep/coreutils — из pkgs
  hookPath = "/opt/homebrew/bin:/usr/local/bin:${lib.makeBinPath [ pkgs.gnugrep pkgs.coreutils ]}";
in {
  # macOS-слой: общие файлы/хуки — те же модули, что у Linux (devpod)
  imports = [
    ./files.nix
    ./hooks.nix
  ];

  home.stateVersion = "26.05";

  home.file = {
    ".hushlogin".source = link "tools/zsh/.hushlogin";
    ".aerospace.toml".source = link "tools/aerospace/.aerospace.toml";
    # trust.json читается по двум путям: ~/.config/homebrew (интерактивный шелл,
    # XDG_CONFIG_HOME задан) и ~/.homebrew (brew bundle из darwin-rebuild, где
    # sudo сохраняет только PATH). Оба ведут на один файл.
    ".homebrew/trust.json".source = link "tools/homebrew/trust.json";
    # новые хосты дописываются сквозь симлинк в tools/git/known_hosts (под git)
    ".ssh/known_hosts".source = link "tools/git/known_hosts";
    # приватные конфиги — из сабмодуля private/; до его init симлинки висячие
    ".ssh/config".source = link "private/ssh/config";
    # rbw на macOS игнорирует XDG_CONFIG_HOME и читает конфиг из Library
    "Library/Application Support/rbw/config.json".source = link "private/rbw/config.json";
    "Library/Application Support/Leader Key/config.json".source = link "tools/leader-key/config.json";
    "Library/Application Support/Cursor/User/settings.json".source = link "tools/vscode/settings.json";
    "Library/Application Support/Cursor/User/keybindings.json".source = link "tools/vscode/keybindings.json";
    "Library/Application Support/Code/User/settings.json".source = link "tools/vscode/settings.json";
    "Library/Application Support/Code/User/keybindings.json".source = link "tools/vscode/keybindings.json";
  };

  xdg.configFile = {
    "ghostty/config".source = link "tools/ghostty/config";
    "direnv/direnvrc".source = link "tools/direnv/direnvrc";
    "homebrew/trust.json".source = link "tools/homebrew/trust.json";
  };

  home.activation = {
    # ControlMaster в private/ssh/config держит мультиплекс-сокеты здесь
    sshSockets = after ''
      run mkdir -p "$HOME/.ssh/sockets"
    '';

    # devpod ставится каской в homebrew-шаге активации nix-darwin, который
    # идёт ДО postActivation (home-manager) — на первом прогоне бинарь уже есть
    setupDevpod = after ''
      export PATH="${hookPath}:$PATH"
      if command -v devpod >/dev/null 2>&1; then
        run devpod context set-options --option DOTFILES_URL=git@github.com:CosmDandy/dotfiles.git --option GIT_SSH_SIGNATURE_FORWARDING=false --option SSH_ADD_PRIVATE_KEYS=true --option SSH_AGENT_FORWARDING=true --option SSH_INJECT_DOCKER_CREDENTIALS=true --option SSH_INJECT_GIT_CREDENTIALS=false \
          || echo "warn: devpod context set-options failed"
        run devpod ide use none || echo "warn: devpod ide use failed"
        # provider add не идемпотентен («already exists» на повторном запуске)
        if ! devpod provider list 2>/dev/null | grep -q "local-docker"; then
          run devpod provider add docker --name local-docker --use -o INACTIVITY_TIMEOUT=1h \
            || echo "warn: provider local-docker not added"
        fi
        # ssh-провайдер требует Host kvt-d-01 из private/ssh/config и доступности
        # хоста — на машине без приватного конфига/VPN не валим активацию
        if ! devpod provider list 2>/dev/null | grep -q "kvt-d-01-ssh"; then
          run devpod provider add ssh --name kvt-d-01-ssh -o HOST=kvt-d-01 \
            || echo "warn: ssh-провайдер kvt-d-01 не настроен (нет ~/.ssh/config или хост недоступен)"
        fi
        run devpod provider use local-docker || echo "warn: provider use failed"
      else
        echo "warn: devpod не найден — настройка providers пропущена"
      fi
    '';

    # apply.sh сам пропускает всё при отсутствии orb CLI (свежая машина,
    # где OrbStack.app ещё не запускался; VM без nested virt)
    applyOrbstack = after ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/orbstack/apply.sh" \
        || echo "warn: orbstack apply failed"
    '';
  };
}
