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
      # "sfm"
      # ----------
      # "secretive"
      "orbstack"
      "leader-key"
      # Браузеры
      "arc"
      "netnewswire"
      # "yattee"
      # Разработка
      "ghostty"
      # "cursor"
      "visual-studio-code"
      "devpod"
      "postico"
      # "utm"
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
      # "element"
      # Системные утилиты
      # каск, а не nixpkgs: bitwarden-desktop тянет electron, помеченный insecure
      "bitwarden"
      "onyx"
      "ukelele"
      "betterdisplay"
      # "jordanbaird-ice"
      # "syncthing-app"
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

  # ===============================
  # CLI Tools & Development Environment
  # ===============================
  environment.systemPackages = with pkgs; [
    nodejs
    python3
    go
    uv
    lua
    luarocks
    eza
    fd
    ripgrep
    iperf3
    unzip
    wget
    curl
    ffmpeg
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
    gdu
    gitleaks
    direnv
    nix-direnv
    rbw
    pinentry_mac
    yamllint
    shellcheck
    blueutil
  ];

  # ===============================
  # System Configuration
  # ===============================
  system = {
    stateVersion = 6;
    primaryUser = "cosmdandy";
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
