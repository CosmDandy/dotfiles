{
  config,
  lib,
  pkgs,
  ...
}:
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
  hookPath = "/opt/homebrew/bin:/usr/local/bin:${
    lib.makeBinPath [
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.zsh
    ]
  }";
in
{
  # macOS-слой: общие файлы/хуки — те же модули, что у Linux (devpod)
  imports = [
    ./files.nix
    ./hooks.nix
  ];

  # Дубль из default.nix: мак его не импортирует (только files/hooks), а без
  # этого мануал HM собирается на каждом darwin-rebuild и тянет ворнинг про
  # options.json без контекста. Подробности — в комментарии в default.nix.
  manual.manpages.enable = false;

  home.stateVersion = "26.05";

  home.file = {
    ".hushlogin".source = link "tools/zsh/.hushlogin";
    # .aerospace.toml и Leader Key/config.json НЕ здесь: их читают login items
    # раньше, чем монтируется /nix; см. хук loginItemConfigs ниже
    # known_hosts НЕ здесь: ssh (UpdateHostKeys) пересоздаёт файл, уничтожая
    # симлинк, — каждый следующий switch упирался бы в бэкап; см. хук ниже
    # приватные конфиги — из сабмодуля private/; до его init симлинки висячие
    # ssh-конфиги — только macOS. В dev-контейнеры не тянутся сознательно: там
    # ssh нужен лишь для git к форжам, и это делает проброшенный агент. Пробовали
    # тянуть — Linux-ssh 9.6 падает целиком («terminating, N bad configuration
    # options») на UseKeychain и на mlkem768x25519, а вместе с ним умирает git.
    ".ssh/config".source = link "private/ssh/config";
    # контуры (kvt, local-lab, cloud-lab) — каталогом целиком, чтобы новый
    # файл подхватывался глобом Include без правки этого списка
    ".ssh/config.d".source = link "private/ssh/config.d";
    # rbw на macOS игнорирует XDG_CONFIG_HOME и читает конфиг из Library
    "Library/Application Support/rbw/config.json".source = link "private/rbw/config.json";
    "Library/Application Support/Cursor/User/settings.json".source = link "tools/vscode/settings.json";
    "Library/Application Support/Cursor/User/keybindings.json".source =
      link "tools/vscode/keybindings.json";
    "Library/Application Support/Code/User/settings.json".source = link "tools/vscode/settings.json";
    "Library/Application Support/Code/User/keybindings.json".source =
      link "tools/vscode/keybindings.json";
  };

  xdg.configFile = {
    "ghostty/config".source = link "tools/ghostty/config";
    # direnvrc переехал в files.nix: nix-direnv нужен и в dev-контейнере,
    # а не только на маке
  };

  home.activation = {
    # Конфиги login items — ПРЯМЫМИ симлинками, не через home.file. /nix живёт
    # на отдельном ЗАШИФРОВАННОМ томе, который нельзя смонтировать до
    # разблокировки ключом пользователя, то есть до логина. Замер загрузки
    # 2026-08-16: 12:40:20 первая попытка монтирования падает («Failed to
    # unwrap metadata crypto state»), 12:40:40 стартуют AeroSpace и Leader Key,
    # и только 12:40:51 том смонтирован. Симлинк через /nix/store в эти 11
    # секунд висячий — приложение молча берёт дефолтный конфиг, отсюда вечное
    # «нажми reload config» у AeroSpace. Прямой симлинк в .dotfiles не
    # пересекает /nix и читается всегда. Тот же довод, что у trust.json ниже.
    loginItemConfigs = after ''
      run ln -sfn "${dotfiles}/tools/aerospace/.aerospace.toml" \
        "$HOME/.aerospace.toml"
      run mkdir -p "$HOME/Library/Application Support/Leader Key"
      run ln -sfn "${dotfiles}/tools/leader-key/config.json" \
        "$HOME/Library/Application Support/Leader Key/config.json"
    '';

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

    # ControlMaster в private/ssh/config держит мультиплекс-сокеты здесь.
    # Только macOS: ssh-конфиг в контейнеры не тянется, там мультиплекса нет.
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

    # Хук seedKnownHosts удалён вместе с самим файлом (2026-08-06): known_hosts
    # копился годами и превратился в карту всей инфраструктуры, куда когда-либо
    # ходили, включая рабочий GitLab с нестандартным портом — в публичном
    # репозитории это готовая цель для разведки. Заводить его заново не нужно:
    # ssh дописывает хосты сам, подтверждение отпечатка делается один раз на хост.

    # devpod ставится каской в homebrew-шаге активации nix-darwin, который
    # идёт ДО postActivation (home-manager) — на первом прогоне бинарь уже есть
    # apply.sh сам пропускает всё при отсутствии devpod CLI и не считает отказом
    # недоступный ssh-провайдер kvt-d-01 (нет private/ssh/config или VPN)
    setupDevpod = beforeReport ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/devpod/apply.sh" \
        || ${warn "devpod apply failed"}
    '';

    # apply.sh сам пропускает всё при отсутствии orb CLI (свежая машина,
    # где OrbStack.app ещё не запускался; VM без nested virt)
    applyOrbstack = beforeReport ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/orbstack/apply.sh" \
        || ${warn "orbstack apply failed"}
    '';
  };
}
