{
  config,
  lib,
  pkgs,
  user,
  hostname,
  cpuCores,
  memoryGiB,
  ...
}:

let
  giB = n: toString (n * 1024 * 1024 * 1024);

  # Параллелизм демона Nix считается от железа (cpuCores/memoryGiB приходят из
  # flake.nix), а не берётся дефолтом. Дефолт — max-jobs = auto, то есть по
  # числу ядер, и cores = 0, то есть каждое задание на все ядра: на восьми
  # ядрах это до 64 компиляторов разом. На 8 ГиБ машина от этого уходит в своп
  # и считает медленнее, чем считала бы с меньшим параллелизмом (наблюдалось
  # 2026-08-09: load average 17.9, своп 8.6 ГиБ из 9.2 при сборке rio).
  #
  # Потолок по памяти: тяжёлая сборка (Rust, C++ с LTO) на пике берёт ~3 ГиБ,
  # ещё ~2 ГиБ остаётся системе. Потолок по ядрам — половина: иначе на машине с
  # большой памятью вышло бы много однопоточных заданий вместо нескольких
  # быстрых, а сборки плохо параллелятся между собой, но хорошо внутри себя.
  nixMaxJobs = lib.max 1 (lib.min (cpuCores / 2) ((memoryGiB - 2) / 3));
  # Ядра делятся между одновременными заданиями, чтобы в сумме не превысить железо.
  nixBuildCores = lib.max 1 (cpuCores / nixMaxJobs);

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
  # Манифест едет в store отдельным путём и приходит в скрипт переменной.
  # writeShellScriptBin создаёт ровно один файл — сам скрипт, — поэтому «файл
  # рядом со скриптом» в store не существует, и агент падал на поиске манифеста
  # (`не найден manifest.conf рядом со скриптом`, restic не писал с 2026-08-06).
  # Держать манифест в store, а не читать из рабочей копии, — по той же причине,
  # по которой там же лежат сами скрипты: иначе откат generation вернул бы
  # старый скрипт, но список путей взял бы сегодняшний.
  backupManifest = ../../automation/backup/manifest.conf;
  backupCheckScript = pkgs.writeShellScriptBin "backup-check" (
    builtins.readFile ../../automation/backup/backup-check.sh
  );
  cleanupMacScript = pkgs.writeShellScriptBin "cleanup-mac" (
    builtins.readFile ../../automation/launchd/scripts/cleanup-mac.sh
  );
  sshDevpodAgentScript = pkgs.writeShellScriptBin "ssh-devpod-agent" (
    builtins.readFile ../../automation/launchd/scripts/ssh-devpod-agent.sh
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
    # terminfo для tmux — явно, вместо снятого environment.enableAllTerminfo.
    # Та опция тянула девять terminfo-пакетов, из которых восемь были не нужны:
    # семь терминалов, которых на этой машине нет (alacritty, kitty, mtm, rio,
    # rxvt-unicode, st, wezterm), плюс мёртвый дубль ghostty — настоящий приезжает
    # из /Applications/Ghostty.app, приложение само выставляет TERMINFO на свой
    # бандл, и эта переменная бьёт весь TERMINFO_DIRS.
    # Нужен был из всей девятки только этот: TERM внутри tmux — tmux-256color, а в
    # системном macOS ncurses он урезан (105 capabilities против 175 здесь) — нет
    # hpa, indn, invis и модифицированных клавиш kDC/kEND/kHOM/kIC/kLFT, то есть
    # shift+стрелки и shift+Home/End в tmux перестают распознаваться.
    # Цена опции была не в мегабайтах: rio собирается из исходников, и на каждом
    # bump'е nixpkgs, который Hydra не успела собрать под aarch64-darwin, обычный
    # `updm` уходил компилировать Rust-терминал с wgpu ради 20 КБ terminfo.
    tmux.terminfo
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
    # Два пейджера диффа для lazygit, переключение клавишей `|`: delta рисует
    # построчный дифф, difftastic сравнивает синтаксические деревья. Оба на
    # испытательном периоде, по итогу один уедет отсюда и из tools/lazygit/*.yml.
    # Раньше стояли императивно (`nix profile install`) — то есть вне
    # конфигурации: пропали бы при пересоздании машины и не попадали в образ.
    delta
    difftastic
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
      EnvironmentVariables.BACKUP_MANIFEST_FILE = "${backupManifest}";
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

    # Отдельный ssh-agent для dev-контейнеров: держит только те два ключа,
    # которыми ходят изнутри контейнера, вместо всего системного агента.
    # Подробности — в шапке самого скрипта; на стороне ssh это `IdentityAgent`
    # в блоке `Host *.devpod` (private/ssh/config).
    #
    # KeepAlive: агент запущен с -D, скрипт висит на wait, поэтому выход
    # процесса означает смерть агента — launchd поднимет заново и переложит
    # ключи. RunAtLoad у user-агента срабатывает после логина, когда Keychain
    # уже разблокирован и ssh-add может взять оттуда пароль.
    ssh-devpod-agent.serviceConfig = {
      ProgramArguments = [ "${sshDevpodAgentScript}/bin/ssh-devpod-agent" ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-devpod-agent.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-devpod-agent.log";
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
    # Настройки демона Nix. Не через `nix.settings` — при `nix.enable = false`
    # (демон принадлежит Determinate) его в конфигурации не существует вовсе.
    # Determinate владеет /etc/nix/nix.conf и перезаписывает его, но сам же
    # подключает оттуда `!include nix.custom.conf` и этот файл не трогает —
    # он и предназначен для пользовательских правок.
    # Прежний nix.custom.conf (два комментария от инсталлятора, ни одной
    # настройки) активация сама уведёт в *.before-nix-darwin — см. `mv` в
    # /etc/static-обходе скрипта activate, ручное вмешательство не нужно.
    etc."nix/nix.custom.conf".text = ''
      # Параллелизм — из cpuCores/memoryGiB в flake.nix, формулы в let выше.
      # На этой машине (8 ядер, 8 ГиБ) выходит max-jobs = ${toString nixMaxJobs}, cores = ${toString nixBuildCores}.
      max-jobs = ${toString nixMaxJobs}
      cores = ${toString nixBuildCores}

      # Дедупликация store хардлинками при добавлении пути. Действует только на
      # новые пути; уже лежащие 6.6 ГБ разово ужимает `nix store optimise`.
      auto-optimise-store = true

      # Страховка от переполнения диска посреди сборки: когда свободного места
      # остаётся меньше min-free, GC чистит store, пока не освободит max-free.
      # max-free задан явно, потому что по умолчанию он бесконечный — то есть
      # сработавший GC выметал бы всё, что не под GC-рутом, а не нужный минимум.
      # Эти два от железа не считаются: они про свободное место на диске, а не
      # про ОЗУ и ядра, и размер тома при eval так же неизвестен.
      min-free = ${giB 1}
      max-free = ${giB 3}
    '';

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
