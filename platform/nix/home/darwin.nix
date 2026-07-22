{ config, lib, pkgs, ... }:
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  after = lib.hm.dag.entryAfter [ "linkGeneration" ];
  # Хуки, чьи warn'ы должны попасть в сводку, обязаны выполниться ДО неё.
  # entryAfter здесь мало: reportWarnings объявлен в hooks.nix (общем с Linux)
  # и перечислить в нём macOS-хуки нельзя — на Linux их не существует.
  beforeReport = lib.hm.dag.entryBetween [ "reportWarnings" ] [ "linkGeneration" ];
  w = import ./warn.nix { inherit config; };
  warn = w.mk;
  # PATH активации минимальный: brew-бинари (devpod, orb) ищем явно,
  # grep/coreutils — из pkgs. zsh нужен для apply.sh (шебанг env zsh): на маке
  # он есть в /bin, но /bin в PATH активации нет, и хук падал с
  # "env: zsh: No such file or directory"
  hookPath = "/opt/homebrew/bin:/usr/local/bin:${lib.makeBinPath [ pkgs.gnugrep pkgs.coreutils pkgs.zsh ]}";
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
    # known_hosts НЕ здесь: ssh (UpdateHostKeys) пересоздаёт файл, уничтожая
    # симлинк, — каждый следующий switch упирался бы в бэкап; см. хук ниже
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
  };

  home.activation = {
    # trust.json — ПРЯМЫМИ симлинками, не через home.file: brew пишет в trust
    # store и отказывается работать с целью в /nix/store («insecure trust
    # store: target directory not owned by the current user»), что валит
    # brew bundle в активации. Два пути: ~/.config/homebrew (интерактивный
    # шелл, XDG_CONFIG_HOME задан) и ~/.homebrew (brew bundle из
    # darwin-rebuild, где sudo сохраняет только PATH).
    homebrewTrust = after ''
      run mkdir -p "$HOME/.homebrew" "$HOME/.config/homebrew"
      run ln -sfn "${dotfiles}/tools/homebrew/trust.json" "$HOME/.homebrew/trust.json"
      run ln -sfn "${dotfiles}/tools/homebrew/trust.json" "$HOME/.config/homebrew/trust.json"
    '';

    # ControlMaster в private/ssh/config держит мультиплекс-сокеты здесь
    sshSockets = after ''
      run mkdir -p "$HOME/.ssh/sockets"
    '';

    # Раскладка Graphite — копией, а не симлинком через home.file: Text Input
    # Sources не принимает симлинк-бандлы, а цель в /nix/store вдобавок не
    # принадлежит пользователю. Тот же довод, по которому копируется known_hosts.
    # Это не косметика: automation/launchd/config/bt-layout.conf ссылается на
    # input source org.sil.ukelele.keyboardlayout.graphitenew.russian, и без
    # установленного бандла демон bt-layout-switch не может вызвать
    # TISEnableInputSource — переключение при подключении клавиатуры отваливается.
    # Источник в сабмодуле assets/, которого может не быть: без него — warn.
    installKeyboardLayout = beforeReport ''
      SRC="${dotfiles}/assets/keymap/Graphite.bundle"
      DEST="$HOME/Library/Keyboard Layouts/Graphite.bundle"
      if [ -d "$SRC" ]; then
        if ! ${pkgs.diffutils}/bin/diff -rq "$SRC" "$DEST" >/dev/null 2>&1; then
          run mkdir -p "$HOME/Library/Keyboard Layouts"
          run cp -R "$SRC/." "$DEST/"
        fi
      else
        ${warn "раскладка Graphite не установлена (сабмодуль assets/ не инициализирован)"}
      fi
    '';

    # known_hosts сеем копией только при отсутствии: дальше файлом владеет
    # ssh (дописывает/пересоздаёт), а не home-manager
    seedKnownHosts = after ''
      if [ ! -e "$HOME/.ssh/known_hosts" ] && [ -f "${dotfiles}/tools/git/known_hosts" ]; then
        run mkdir -p "$HOME/.ssh"
        run cp "${dotfiles}/tools/git/known_hosts" "$HOME/.ssh/known_hosts"
        run chmod 644 "$HOME/.ssh/known_hosts"
      fi
    '';

    # devpod ставится каской в homebrew-шаге активации nix-darwin, который
    # идёт ДО postActivation (home-manager) — на первом прогоне бинарь уже есть
    setupDevpod = beforeReport ''
      export PATH="${hookPath}:$PATH"
      if command -v devpod >/dev/null 2>&1; then
        run devpod context set-options --option DOTFILES_URL=git@github.com:CosmDandy/dotfiles.git --option GIT_SSH_SIGNATURE_FORWARDING=false --option SSH_ADD_PRIVATE_KEYS=true --option SSH_AGENT_FORWARDING=true --option SSH_INJECT_DOCKER_CREDENTIALS=true --option SSH_INJECT_GIT_CREDENTIALS=false \
          || ${warn "devpod context set-options failed"}
        run devpod ide use none || ${warn "devpod ide use failed"}
        # provider add не идемпотентен («already exists» на повторном запуске)
        if ! devpod provider list 2>/dev/null | grep -q "local-docker"; then
          run devpod provider add docker --name local-docker --use -o INACTIVITY_TIMEOUT=1h \
            || ${warn "provider local-docker not added"}
        fi
        # ssh-провайдер требует Host kvt-d-01 из private/ssh/config и доступности
        # хоста — на машине без приватного конфига/VPN не валим активацию
        if ! devpod provider list 2>/dev/null | grep -q "kvt-d-01-ssh"; then
          run devpod provider add ssh --name kvt-d-01-ssh -o HOST=kvt-d-01 \
            || ${warn "ssh-провайдер kvt-d-01 не настроен (нет ~/.ssh/config или хост недоступен)"}
        fi
        run devpod provider use local-docker || ${warn "provider use failed"}
      else
        ${warn "devpod не найден — настройка providers пропущена"}
      fi
    '';

    # apply.sh сам пропускает всё при отсутствии orb CLI (свежая машина,
    # где OrbStack.app ещё не запускался; VM без nested virt)
    applyOrbstack = beforeReport ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/orbstack/apply.sh" \
        || ${warn "orbstack apply failed"}
    '';
  };
}
