{ config, pkgs, ... }:

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
      autoUpdate = true;
      cleanup = "zap";
      upgrade = true;
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
      # "claude"
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
    nodejs_24   # явная мажорная версия: hooks.nix уже на nodejs_24, иначе разъедутся
    python3
    go
    uv
    luarocks  # нужен mason'у (luacheck); свой lua тащит с собой, отдельный пакет lua не нужен
    eza
    fd
    ripgrep
    fzf       # интерактивный выбор: dpkey (воркспейс devpod), kubectx/kubens. В Linux-профиле уже есть (home/default.nix)
    ipmitool  # IPMI-доступ к BMC серверов (IMM/iLO/iDRAC): питание, SOL-консоль, сенсоры
    unzip
    curl
    jq
    starship
    neovim
    tree-sitter  # CLI: nvim-treesitter (main) компилирует парсеры через него (на Linux ставится npm-ом в install.sh)
    tmux
    atuin
    btop
    git
    gh        # GitHub CLI
    glab      # GitLab CLI
    lazygit
    lazydocker
    lima      # декларативные Linux-VM (PXE-стенд)
    iperf3    # замеры пропускной способности (PXE-стенд, будущий 10G)
    ansible
    gdu
    gitleaks
    restic    # бэкап в Hetzner Object Storage, automation/backup/backup.sh
    direnv
    nix-direnv
    rbw
    pinentry_mac
    sops
    age
    zizmor    # статический анализ GitHub Actions workflow (pre-commit + CI)
    yamllint
    shellcheck
  ];

  # ===============================
  # System Configuration
  # ===============================
  system = {
    stateVersion = 6;
    primaryUser = "cosmdandy";
  };

  # ===============================
  # Подсветка активного окна (JankyBorders).
  # Aerospace фокус визуально никак не отмечает, а menu bar скрыт — рамка
  # остаётся единственным индикатором «где ввод». Цвета из solarized-osaka,
  # той же палитры, что nvim и ghostty.
  # ===============================
  services.jankyborders = {
    enable = true;
    style = "round";        # повторяет скругление окон macOS
    width = 3.0;
    hidpi = true;           # рамка без лесенки на retina
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
      ProgramArguments = [ "/bin/bash" "/Users/${config.system.primaryUser}/.dotfiles/automation/backup/backup.sh" ];
      StartCalendarInterval = [ { Hour = 13; Minute = 0; } ];
      RunAtLoad = false;
      # Бэкап не должен конкурировать за диск с интерактивной работой
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "/tmp/backup.log";
      StandardErrorPath = "/tmp/backup.log";
    };

    # Сторож бэкапа, через два часа после него. Отдельным агентом, а не хвостом
    # backup.sh: тот жалуется, когда упал, но молчит, когда его вообще не
    # запустили — а это и есть типичный отказ. Сторож смотрит на возраст
    # последнего снапшота, поэтому ловит и такой случай, и сломанные доступы.
    backup-check.serviceConfig = {
      ProgramArguments = [
        "/bin/bash"
        "/Users/${config.system.primaryUser}/.dotfiles/automation/backup/backup-check.sh"
        "--quiet"
      ];
      StartCalendarInterval = [ { Hour = 15; Minute = 0; } ];
      RunAtLoad = false;
      LowPriorityIO = true;
      Nice = 5;
      StandardOutPath = "/tmp/backup-check.log";
      StandardErrorPath = "/tmp/backup-check.log";
    };

    cleanup-mac.serviceConfig = {
      ProgramArguments = [ "/bin/bash" "/Users/${config.system.primaryUser}/.dotfiles/automation/launchd/scripts/cleanup-mac.sh" ];
      StartCalendarInterval = [ { Weekday = 0; Hour = 12; Minute = 0; } ];
      RunAtLoad = false;
      StandardOutPath = "/tmp/cleanup-mac.log";
      StandardErrorPath = "/tmp/cleanup-mac.log";
    };

    # Демон переключения раскладки при подключении BT-клавиатуры. Бинарь
    # собирает platform/macos/install-bt-layout.sh; TCC-права привязаны к
    # bundle-id бинаря (com.cosmdandy.bt-layout-switch) — смена launchd-лейбла
    # их не сбрасывает.
    bt-layout-switch.serviceConfig = {
      ProgramArguments = [ "/Users/${config.system.primaryUser}/.dotfiles/automation/launchd/scripts/bt-layout-switch.app/Contents/MacOS/bt-layout-switch" ];
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
        BT_LAYOUT_CONF = "/Users/${config.system.primaryUser}/.dotfiles/automation/launchd/config/bt-layout.conf";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/bt-layout-switch.log";
      StandardErrorPath = "/tmp/bt-layout-switch.log";
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
    hostName = "macbook-${config.system.primaryUser}";
    localHostName = "macbook-${config.system.primaryUser}";
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
