{ config, pkgs, ... }:

{
  # ===============================
  # macOS Configuration with nix-darwin
  # ===============================

  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "@admin" ];
    };
  };

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
      # ----------
      # "secretive"
      "orbstack"
      "leader-key"
      # Браузеры
      "arc"
      "netnewswire"
      "yattee"
      # Разработка
      "ghostty"
      "cursor"
      "visual-studio-code"
      "devpod"
      "utm"
      # AI инструменты
      "chatgpt"
      "claude"
      "lm-studio"
      # Продуктивность
      "obsidian"
      "timing"
      "raycast"
      # Коммуникации
      "telegram"
      # Системные утилиты
      "onyx"
      "ukelele"
      "betterdisplay"
      "jordanbaird-ice"
      "syncthing-app"
      # Дополнительные утилиты
      "flux"
      # Оконный менеджер
      "nikitabobko/tap/aerospace"
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
    rustc
    cargo
    eza
    fd
    ripgrep
    iperf3
    unzip
    wget
    curl
    ffmpeg
    jq
    terraform
    ansible
    starship
    claude-code
    neovim
    tmux
    atuin
    btop
    git
    gh        # GitHub CLI
    glab      # GitLab CLI
    lnav      # Log file navigator
    lazygit
    lazydocker
    dive
    k9s
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

#  nix.gc = {
#    automatic = true;
#    interval = { Weekday = 0; Hour = 2; Minute = 0; };
#    options = "--delete-older-than 30d";
#  };

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
      persistent-apps = [
        "/System/Applications/Launchpad.app"
      ];
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
