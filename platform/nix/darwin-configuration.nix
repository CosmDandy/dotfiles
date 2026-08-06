{
  config,
  pkgs,
  user,
  hostname,
  ...
}:

let
  # Скрипты launchd-агентов заворачиваются в store-путь, а не исполняются из
  # рабочей копии: агент декларирован в nix, но раньше выполнялось то, что
  # лежит в /Users/.../.dotfiles в момент запуска — откат generation вернёт
  # plist, но не скрипт, а `git checkout` другой ветки молча меняет то, что
  # работает по расписанию.
  #
  # writeShellScriptBin, а НЕ writeShellApplication: последний принудительно
  # добавляет `set -euo pipefail` и гоняет shellcheck в checkPhase (сборка бы
  # падала). Эти три скрипта осознанно не используют -e (см. их же
  # комментарии и tools/claude/custom/rules/shell.md) — например
  # backup-check.sh делает `check_output=$(restic check ...); check_exit=$?`
  # специально, чтобы отличить «залочено», «недоступно» и «повреждено» по
  # содержимому вывода, а не падать на первом ненулевом коде (см. инцидент
  # 2026-07-26 в комментариях самого скрипта); cleanup-mac.sh должен пережить
  # permission-denied у `du` в одной директории и почистить остальные. Оба
  # сценария `set -e` от writeShellApplication сломал бы.
  # Оригинальный shebang файла (#!/usr/bin/env bash) остаётся первой строкой
  # текста и становится безобидным комментарием второй строкой результата —
  # writeShellScriptBin ставит свой шебанг сам.
  backupScript = pkgs.writeShellScriptBin "backup" (
    builtins.readFile ../../automation/backup/backup.sh
  );
  backupCheckScript = pkgs.writeShellScriptBin "backup-check" (
    builtins.readFile ../../automation/backup/backup-check.sh
  );
  cleanupMacScript = pkgs.writeShellScriptBin "cleanup-mac" (
    builtins.readFile ../../automation/launchd/scripts/cleanup-mac.sh
  );
in
{
  # ===============================
  # macOS Configuration with nix-darwin
  # ===============================

  # Nix daemon managed by Determinate Nix installer
  nix.enable = false;

  # ===============================
  # Homebrew Management
  # ===============================
  homebrew = {
    enable = true;
    onActivation = {
      # autoUpdate/upgrade выключены: при true каждый darwin-rebuild switch
      # ходит в сеть и обновляет все каски — один и тот же коммит даёт разный
      # результат в разные дни, а --rollback каски не откатывает (brew этого
      # не умеет). Плюс любой сбой brew (сеть, битый тап) валит всю активацию
      # nix-darwin. Обновление касков — отдельный явный шаг (см. updm).
      # cleanup остаётся "zap": намеренно — снятие каска из списка удаляет
      # его С ДАННЫМИ (custom/rules/nix.md), это осознанное поведение,
      # не связанное с воспроизводимостью самой активации.
      autoUpdate = false;
      cleanup = "zap";
      upgrade = false;
    };
    casks = [
      # with password
      "karabiner-elements"
      "microsoft-teams"
      "openvpn-connect"
      "amneziavpn"
      # "secretive"
      "orbstack"
      "leader-key"
      # Браузеры
      "arc"
      "netnewswire"
      # Разработка
      "ghostty"
      # "cursor"
      "visual-studio-code"
      "devpod"
      "postico"
      "utm"
      # AI инструменты
      # "chatgpt"
      "claude"
      # "lm-studio"
      # Продуктивность
      "obsidian"
      "timing"
      "raycast"
      # Коммуникации
      "telegram"
      # Системные утилиты
      "bitwarden"
      "onyx"
      "ukelele"
      "betterdisplay"
      # "jordanbaird-ice"
      # Дополнительные утилиты
      "flux-app"
      # Оконный менеджер
      "nikitabobko/tap/aerospace"
      "spokenly"
    ];
    taps = [
      "nikitabobko/tap"
    ];
  };

  # brew оставляет .pkg/.dmg инсталляторы касков после установки и не чистит их
  # никогда: cleanup=zap трогает только старые версии, а это «текущие». Удаление
  # касков идёт по pkgutil-receipts, инсталляторы в цепочке не участвуют (790M → 38M).
  # Директории версий не трогаем — по ним brew определяет установленную версию.
  system.activationScripts.postActivation.text = ''
    find /opt/homebrew/Caskroom -maxdepth 3 -type f \
      \( -name '*.pkg' -o -name '*.dmg' -o -name '*.zip' \) -delete 2>/dev/null || true
  '';

  # ===============================
  # CLI Tools & Development Environment
  # ===============================
  environment.systemPackages = with pkgs; [
    nodejs_24 # явная мажорная версия: hooks.nix уже на nodejs_24, иначе разъедутся
    python3
    go
    uv
    luarocks # нужен mason'у (luacheck); свой lua тащит с собой, отдельный пакет lua не нужен
    eza
    fd
    ripgrep
    fzf # интерактивный выбор: dpkey (воркспейс devpod), kubectx/kubens. В Linux-профиле уже есть (home/default.nix)
    ipmitool # IPMI-доступ к BMC серверов (IMM/iLO/iDRAC): питание, SOL-консоль, сенсоры
    unzip
    curl
    jq
    starship
    neovim
    tree-sitter # CLI: nvim-treesitter (main) компилирует парсеры через него (на Linux ставится npm-ом в install.sh)
    tmux
    # tmux-thumbs объявлен и здесь, а не только в Linux-профиле: .tmux.conf один
    # на обе среды и грузит плагин по `if-shell [ -e ~/.nix-profile/... ]`, поэтому
    # на маке файла не было и prefix+f молча ничего не делал — при живой
    # конфигурации на 20 строк в .tmux.conf.
    tmuxPlugins.tmux-thumbs
    atuin
    btop
    git
    gh # GitHub CLI
    glab # GitLab CLI
    lazygit
    lazydocker
    lima # декларативные Linux-VM (PXE-стенд)
    iperf3 # замеры пропускной способности (PXE-стенд, будущий 10G)
    ansible
    gdu
    gitleaks
    restic # бэкап в Hetzner Object Storage, automation/backup/backup.sh
    direnv
    nix-direnv
    rbw
    pinentry_mac
    sops
    age
    zizmor # статический анализ GitHub Actions workflow (pre-commit + CI)
    yamllint
    shellcheck
    # Тулинг для языка, на котором написан сам этот файл. До сих пор его не было
    # вовсе: flake.nix и home/*.nix редактировались как простой текст, а правило
    # `nixfmt --check` из custom/rules/nix.md было неисполнимо — бинаря в системе нет
    # (проверено: все шесть .nix не отформатированы). Не через mason: там `nil`
    # ставится через cargo, которого в системе нет, и установка молча падает.
    nil # LSP: переход к определению, диагностика опечаток в именах опций
    nixfmt # официальный форматтер (RFC 166) — его же зовут правила и CI
    statix # анти-паттерны
    deadnix # неиспользуемые аргументы и let-биндинги
  ];

  # ===============================
  # System Configuration
  # ===============================
  system = {
    stateVersion = 6;
    # Приходит параметром из flake.nix (mkDarwin), а не живёт константой здесь —
    # иначе на другого пользователя нужен был бы sed по трекаемому файлу (было
    # в install-nix.sh, убрано).
    primaryUser = user;
  };

  # ===============================
  # Подсветка активного окна (JankyBorders).
  # Aerospace фокус визуально никак не отмечает, а menu bar скрыт — рамка
  # остаётся единственным индикатором «где ввод». Цвета из solarized-osaka,
  # той же палитры, что nvim и ghostty.
  # ===============================
  services.jankyborders = {
    enable = true;
    style = "round"; # повторяет скругление окон macOS
    width = 3.0;
    hidpi = true; # рамка без лесенки на retina
    # order=below прячет рамку под окно, наружу торчит половина ширины — при
    # развёрнутом на весь экран окне она обрезается краем экрана и подсветка
    # пропадает. above кладёт поверх окна; отступ ей даёт gaps.outer=4
    # в .aerospace.toml.
    order = "above";
    # Тема переключается между solarized light и dark, поэтому цвет взят
    # средним по светлоте: контрастирует и с кремовым #fdf6e3, и с тёмным
    # #002b36. Синий sol_blue на светлой теме проваливался.
    active_color = "0xff248d83";
    # Неактивные окна без рамки вовсе: подсветка тогда однозначно значит
    # «сюда уйдёт ввод», а не соревнуется за внимание с соседями.
    inactive_color = "0x00000000";
  };

  # ===============================
  # Launchd-агенты («кроны») — декларативно, ставятся darwin-rebuild switch.
  # Лейблы у nix-darwin с префиксом org.nixos.*; старые com.cosmdandy.*
  # выгружает миграционный хук removeLegacyLaunchAgents (home/darwin.nix).
  # timing-mcp не здесь — им владеет tools/claude/custom/install.sh.
  # ===============================
  launchd.user.agents = {
    # Ежедневно в 13:00. Днём, а не ночью: ноутбук ночью спит, а launchd,
    # в отличие от systemd с Persistent=true, пропущенный календарный
    # запуск не догоняет.
    backup.serviceConfig = {
      ProgramArguments = [ "${backupScript}/bin/backup" ];
      StartCalendarInterval = [
        {
          Hour = 13;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      # Бэкап не должен конкурировать за диск с интерактивной работой
      LowPriorityIO = true;
      Nice = 5;
      # /tmp чистится macOS при перезагрузке — лог инцидента старше суток
      # исчезал раньше, чем до него доходили руки. Library/Logs переживает reboot.
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/backup.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/backup.log";
    };

    # Сторож бэкапа, через два часа после него. Отдельным агентом, а не хвостом
    # backup.sh: тот жалуется, когда упал, но молчит, когда его вообще не
    # запустили — а это и есть типичный отказ. Сторож смотрит на возраст
    # последнего снапшота, поэтому ловит и такой случай, и сломанные доступы.
    backup-check.serviceConfig = {
      ProgramArguments = [
        "${backupCheckScript}/bin/backup-check"
        "--quiet"
      ];
      StartCalendarInterval = [
        {
          Hour = 15;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/backup-check.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/backup-check.log";
    };

    cleanup-mac.serviceConfig = {
      ProgramArguments = [ "${cleanupMacScript}/bin/cleanup-mac" ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 12;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/cleanup-mac.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/cleanup-mac.log";
    };

    # Демон переключения раскладки при подключении BT-клавиатуры. Бинарь
    # собирает platform/macos/install-bt-layout.sh; TCC-права привязаны к
    # bundle-id бинаря (com.cosmdandy.bt-layout-switch) — смена launchd-лейбла
    # их не сбрасывает.
    #
    # Сознательно НЕ store-путь (в отличие от backup/backup-check/cleanup-mac
    # выше): это не shell-скрипт, а собранный и подписанный .app-бандл, у
    # которого Bluetooth/Accessibility-разрешения в TCC привязаны к пути и
    # bundle-id конкретного бинаря. Заворачивание в nix store означает, что путь
    # менялся бы при каждой пересборке — пользователю пришлось бы заново
    # подтверждать оба разрешения на каждом darwin-rebuild switch. Компиляция
    # Swift с entitlements внутри самого flake (без отдельного шага подписи)
    # тоже не встраивается сюда без потери этой стабильности пути.
    bt-layout-switch.serviceConfig = {
      ProgramArguments = [
        "/Users/${config.system.primaryUser}/.dotfiles/automation/launchd/scripts/bt-layout-switch.app/Contents/MacOS/bt-layout-switch"
      ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
        BT_LAYOUT_CONF = "/Users/${config.system.primaryUser}/.dotfiles/automation/launchd/config/bt-layout.conf";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/bt-layout-switch.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/bt-layout-switch.log";
    };

    # Саммари созвонов из anarlog через Claude (claude -p, подписка Max):
    # штатная кнопка anarlog даёт ~40/100 против ручного разбора, этот путь — 86/100
    # ценой $0 сверх подписки. Раз в 15 минут вместо watcher'а на файлы — саммари
    # доступно не сразу после созвона, а разница не критична, и не нужно гадать,
    # в какой момент anarlog допишет транскрипт в базу. Не требует закрытия anarlog:
    # запись в session_documents переживает и работу, и выход приложения (проверено).
    #
    # Сознательно НЕ store-путь: скрипт читает prompt.md через
    # Path(__file__).parent — если бы .py копировался в store через
    # writers.writePython3Bin, __file__ указывал бы в store, а prompt.md
    # остался бы лежать в репозитории рядом с оригиналом и не нашёлся бы.
    # Пришлось бы либо тащить prompt.md в store вторым файлом, либо менять
    # сам скрипт под путь через переменную окружения — за рамками того, что
    # просили в 7.6 (для python "можно оставить"). Секретов на входе нет,
    # только чтение sqlite и вызов `claude -p`, так что риск от привязки к
    # working copy ниже, чем у launchd-скриптов на bash.
    meeting-summary.serviceConfig = {
      ProgramArguments = [
        "/Users/${config.system.primaryUser}/.dotfiles/automation/meeting/summarize-meeting.py"
        "--save-to"
        "/Users/${config.system.primaryUser}/Recordings/calls"
      ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/Users/${config.system.primaryUser}/.local/bin:/usr/bin:/bin";
      };
      StartInterval = 900;
      RunAtLoad = false;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/meeting-summary.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/meeting-summary.log";
    };
  };

  # ===============================
  # Fonts
  # ===============================
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  # nix.gc requires nix.enable = true
  # Run manually: nix-collect-garbage --delete-older-than 30d
  # nix.gc = {
  #   automatic = true;
  #   interval = { Weekday = 0; Hour = 2; Minute = 0; };
  #   options = "--delete-older-than 30d";
  # };

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
    };
  };

  # ===============================
  # Additional System Settings
  # ===============================
  # sudo по отпечатку: /etc/pam.d/sudo_local уже под управлением nix-darwin
  # (симлинк в /etc/static), опция дописывает в него pam_tid.so.
  # reattach обязателен для tmux/screen: там процесс отвязан от Aqua-сессии,
  # без pam_reattach.so запрос TouchID просто не всплывает и sudo падает в
  # пароль. Пароль остаётся рабочим фолбэком (по Enter или при закрытой крышке).
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  documentation = {
    enable = false;
    doc.enable = false;
    info.enable = false;
    man.enable = true;
  };

  environment = {
    enableAllTerminfo = true;
    variables = {
      BROWSER = "arc";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
      # brew: без телеметрии и подсказок-нотаций
      HOMEBREW_NO_ANALYTICS = "1";
      HOMEBREW_NO_ENV_HINTS = "1";
    };
  };

  users.users.${config.system.primaryUser} = {
    name = config.system.primaryUser;
    home = "/Users/${config.system.primaryUser}";
    shell = pkgs.zsh;
  };

  networking = {
    # hostname приходит параметром из flake.nix (mkDarwin), а не выводится из
    # primaryUser: раньше имя атрибута конфигурации (macbook-cosmdandy) и
    # networking.hostName были связаны только через primaryUser и разошлись бы
    # на другом пользователе.
    hostName = hostname;
    localHostName = hostname;

    # Файрвол был выключен: FileVault, SIP и Gatekeeper включены, а входящие
    # соединения не фильтровались никак. Машина регулярно бывает в чужих сетях
    # (офис, коворкинг), и любой слушающий порт — dev-сервер, kubectl
    # port-forward, restic на время восстановления — был доступен всей подсети.
    #
    # blockAllIncoming = false осознанно: полная блокировка рвёт AirDrop,
    # Handoff и локальные dev-серверы, к которым ходишь с телефона. Режим
    # «пускать подписанное» закрывает то, что нужно закрыть, и не мешает.
    applicationFirewall = {
      enable = true;
      blockAllIncoming = false;
      allowSigned = true; # системные службы Apple
      allowSignedApp = true; # подписанное стороннее (ghostty, orbstack)
      # не отвечать на ping и на пробы закрытых портов: в чужой сети машина
      # просто не видна сканеру
      enableStealthMode = true;
    };
  };

  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      tilesize = 56;
      expose-group-apps = true;
      show-recents = false;
      minimize-to-application = true;
      static-only = false;
      show-process-indicators = true;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
      # Пустой список: nix-darwin вычищает закреплённые приложения — в доке
      # остаются только Finder, запущенные, Downloads (persistent-others) и
      # Корзина. Закомментированный блок = док не управляется вовсе (после
      # 8fe6b2f свежая машина оставалась с дефолтным набором Apple-приложений)
      persistent-apps = [ ];
      persistent-others = [
        "/Users/${config.system.primaryUser}/Downloads"
      ];
    };
    finder = {
      AppleShowAllExtensions = false;
      FXDefaultSearchScope = "SCcf";
      ShowPathbar = true;
      ShowStatusBar = true;
      FXEnableExtensionChangeWarning = true;
      FXPreferredViewStyle = "clmv";
      FXRemoveOldTrashItems = true;
      _FXSortFoldersFirst = true;
      _FXSortFoldersFirstOnDesktop = true;
      NewWindowTarget = "Home";
    };
    NSGlobalDomain = {
      _HIHideMenuBar = true;
      AppleInterfaceStyleSwitchesAutomatically = true;
      KeyRepeat = 2;
      InitialKeyRepeat = 10;
      NSDocumentSaveNewDocumentsToCloud = false;
      NSTableViewDefaultSizeMode = 2;
    };
    WindowManager = {
      EnableStandardClickToShowDesktop = false;
    };
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = false;
    };
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = false;
    };
  };
}
