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

  # NOTE: parallelism is computed from the hardware declared in flake.nix, never
  # left at the default — `max-jobs = auto` with `cores = 0` put 8 cores into
  # swap (2026-08-09).
  nixMaxJobs = lib.max 1 (lib.min (cpuCores / 2) ((memoryGiB - 2) / 3));
  nixBuildCores = lib.max 1 (cpuCores / nixMaxJobs);

  # launchd scripts live in the store, not in the working copy: a generation
  # rollback must move the script together with its plist.
  # NOTE: writeShellScriptBin, not writeShellApplication — the latter forces
  # `set -euo pipefail`, and these scripts parse exit codes by hand on purpose.
  backupScript = pkgs.writeShellScriptBin "backup" (
    builtins.readFile ../../automation/backup/backup.sh
  );
  # NOTE: the manifest is its own store path passed in by env var.
  # writeShellScriptBin creates exactly one file, so "next to the script" does
  # not exist in the store.
  backupManifest = ../../automation/backup/manifest.conf;
  backupCheckScript = pkgs.writeShellScriptBin "backup-check" (
    builtins.readFile ../../automation/backup/backup-check.sh
  );
  cleanupMacScript = pkgs.writeShellScriptBin "cleanup-mac" (
    builtins.readFile ../../automation/launchd/scripts/cleanup-mac.sh
  );
  orphanCheckScript = pkgs.writeShellScriptBin "orphan-check" (
    builtins.readFile ../../automation/launchd/scripts/orphan-check.sh
  );
  waitNixReloadScript = pkgs.writeShellScriptBin "wait-nix-reload" (
    builtins.readFile ../../automation/launchd/scripts/wait-nix-reload.sh
  );
  sshDevpodAgentScript = pkgs.writeShellScriptBin "ssh-devpod-agent" (
    builtins.readFile ../../automation/launchd/scripts/ssh-devpod-agent.sh
  );
  sshSignKeyScript = pkgs.writeShellScriptBin "ssh-sign-key" (
    builtins.readFile ../../automation/launchd/scripts/ssh-sign-key.sh
  );

  # ProgramArguments для агента, который стартует ПРИ ЛОГИНЕ.
  #
  # Прямая ссылка на store-путь для такого агента не работает: /nix лежит на
  # отдельном зашифрованном томе с `noauto` и монтируется determinate-nixd
  # последней фазой инициализации — замерено 2026-08-16: загрузка 12:40:15,
  # login items 12:40:40, /nix только в 12:40:51. В момент запуска исполняемого
  # файла ещё нет, launchd не может его породить и ставит job код 78 (EX_CONFIG).
  # KeepAlive не спасает: launchd после серии неудачных попыток перестаёт
  # пробовать — так и оставались мёртвыми ssh-devpod-agent (KeepAlive = true) и
  # ssh-sign-key, пока их не пнёшь руками после каждой перезагрузки.
  #
  # /bin/bash существует всегда, поэтому порождение удаётся сразу, а ожидание
  # тома происходит уже ВНУТРИ job. mount(8), а не `test -d`: точка
  # монтирования /nix создаётся synthetic.conf в самом начале загрузки и
  # существует задолго до тома.
  #
  # Агентам по расписанию (backup, orphan-check) эта обёртка не нужна — они
  # стартуют много позже загрузки, когда том уже на месте.
  awaitNix = program: [
    "/bin/bash"
    "-c"
    "until /sbin/mount | grep -q ' on /nix ('; do sleep 1; done; exec ${program}"
  ];
in
{
  # NOTE: the daemon belongs to Determinate, so no `nix.*` option exists here.
  nix.enable = false;

  # Homebrew
  homebrew = {
    enable = true;
    onActivation = {
      # autoUpdate/upgrade off: otherwise one commit gives different results on
      # different days and `--rollback` cannot roll casks back. Updates go
      # through updm.
      # NOTE: cleanup = "zap" means dropping a cask from this list — even
      # commenting it out — uninstalls the app WITH ITS DATA on the next switch.
      autoUpdate = false;
      cleanup = "zap";
      upgrade = false;
    };
    casks = [
      # with password
      "karabiner-elements"
      "microsoft-teams"
      "openvpn-connect"
      # amneziavpn
      # "secretive"
      "orbstack"
      "leader-key"
      # Browsers
      "arc"
      "netnewswire"
      # Development
      "ghostty"
      # "cursor"
      "visual-studio-code"
      "devpod"
      "postico"
      "utm"
      # AI
      # "chatgpt"
      "claude"
      # "lm-studio"
      # Productivity
      "obsidian"
      "timing"
      "raycast"
      # Communication
      "telegram"
      # System utilities
      "onyx"
      "betterdisplay"
      # "jordanbaird-ice"
      "flux-app"
      # Window manager
      "nikitabobko/tap/aerospace"
      "spokenly"
      # Utilities
      "logi-options+"
      "tailscale-app"
      "yandextelemost"
      "horos"
    ];
    brews = [
      # NOTE: required by masApps below — brew bundle refuses `mas "…"` lines
      # without it and takes the whole activation down.
      "mas"
    ];
    # NOTE: mas installs only what is already attached to the Apple ID — the one
    # manual step on a fresh machine.
    masApps = {
      "Happ" = 6504287215;
    };
    taps = [
      "nikitabobko/tap"
    ];
  };

  # brew never removes the .pkg/.dmg installers it downloads (790M → 38M here).
  # NOTE: version directories stay — brew reads the installed version from them.
  system.activationScripts.postActivation.text = ''
    find /opt/homebrew/Caskroom -maxdepth 3 -type f \
      \( -name '*.pkg' -o -name '*.dmg' -o -name '*.zip' \) -delete 2>/dev/null || true

    # NOTE: pmset, not power.sleep — the latter goes through systemsetup and
    # cannot split AC from battery. On AC the system never idle-sleeps so
    # background agents keep running; a blanked display plus
    # screensaver.askForPassword = a locked Mac.
    pmset -c sleep 0 displaysleep 8
    pmset -b sleep 1 displaysleep 2 lowpowermode 1
  '';

  # Unattended agents must survive a kernel panic. restartAfterPowerFailure is
  # unsupported on Apple Silicon laptops.
  power.restartAfterFreeze = true;

  environment.systemPackages = with pkgs; [
    nodejs_24 # explicit major: hooks.nix pins the same one
    # NOTE: mason's own runtimes, not languages written on this machine. node
    # installs most of the LSP servers, python3 backs debugpy and mypy (and
    # basedpyright is useless without an interpreter), go builds
    # jsonnet-language-server. Drop any of them and mason fails that package on
    # every install — the failure is a warning, not an error, so the server is
    # simply missing until someone opens the log.
    # NOTE: go WITHOUT its toolchain on purpose. gopls, gotools, gofumpt, delve
    # and golangci-lint only matter for writing Go here, which now happens in
    # Linux. Removing go itself instead would mean dropping
    # jsonnet-language-server from the mason list in tools/nvim.
    python3
    go
    uv
    luarocks # for mason (luacheck); brings its own lua
    eza
    fd
    ripgrep
    fzf # interactive pickers: dpkey, kubectx/kubens
    ipmitool # BMC access: power, SOL console, sensors
    arp-scan # answers even from hosts with every port closed; needs root and own L2 segment
    unzip
    curl
    jq
    starship
    neovim
    tree-sitter # CLI used by nvim-treesitter (main) to compile parsers
    tmux
    # NOTE: this one terminfo instead of environment.enableAllTerminfo (nine
    # packages, one of them rio, which builds from source on every uncached
    # bump). macOS ncurses ships a truncated tmux-256color — 105 capabilities
    # against 175 — so shift+arrows and shift+Home/End stop being recognised
    # inside tmux.
    tmux.terminfo
    # NOTE: declared for macOS too — .tmux.conf is shared and loads the plugin
    # by file existence, so without it prefix+f silently did nothing here.
    tmuxPlugins.tmux-thumbs
    atuin
    btop
    git
    gh
    glab
    lazygit
    delta # diff renderer for lazygit
    lazydocker
    lima # declarative Linux VMs (PXE bench)
    gdu
    gitleaks
    restic # automation/backup/backup.sh
    direnv
    nix-direnv
    rbw
    pinentry_mac
    sops
    age
    # NOTE: these three are called by tools/claude/hooks/posttooluse-lint.sh
    # through the shell PATH, where mason's copies are invisible. The helper
    # returns 0 when a binary is missing, so removing them does not break
    # anything visibly — it silently stops linting every file edited here.
    yamllint
    shellcheck
    ansible-lint
    nil # LSP for this very file
    nixfmt # official formatter (RFC 166), called by rules and CI
    statix # anti-patterns
    deadnix # unused args and let-bindings
  ];

  system = {
    stateVersion = 6;
    # Comes from flake.nix (mkDarwin) so the flake stays a function of the
    # commit — install-nix.sh used to sed this into a tracked file.
    primaryUser = user;
  };

  # Launchd agents, applied by darwin-rebuild switch. nix-darwin labels them
  # org.nixos.*; timing-mcp is not here, it belongs to
  # tools/claude/custom/install.sh.
  launchd.user.agents = {
    # NOTE: 13:00, not at night — the laptop sleeps, and launchd does not catch
    # up a missed calendar run the way systemd's Persistent=true does.
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
      LowPriorityIO = true;
      Nice = 5;
      # NOTE: Library/Logs, not /tmp — macOS wipes /tmp on reboot and incident
      # logs disappeared before anyone read them.
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/backup.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/backup.log";
    };

    # NOTE: a separate agent, not a tail of backup.sh — a script can report that
    # it failed, but not that it was never started, and that is the typical
    # failure.
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

    # Report-only: dangling references to software that is gone. An hour after
    # cleanup-mac so the two do not compete for disk and Spotlight.
    orphan-check.serviceConfig = {
      ProgramArguments = [
        "${orphanCheckScript}/bin/orphan-check"
        "--quiet"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 13;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/orphan-check.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/orphan-check.log";
    };

    # Guards the boot race: /nix mounts ~11s after login items start, so configs
    # symlinked through the store dangle and AeroSpace falls back to defaults.
    # NOTE: PATH is set explicitly — launchd hands out an empty one, and the
    # aerospace CLI comes from a cask in /opt/homebrew/bin.
    wait-nix-reload.serviceConfig = {
      ProgramArguments = awaitNix "${waitNixReloadScript}/bin/wait-nix-reload";
      EnvironmentVariables = {
        PATH = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
      RunAtLoad = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/wait-nix-reload.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/wait-nix-reload.log";
    };

    # A dedicated ssh-agent for dev containers, narrowing what `IdentityAgent`
    # in the `Host *.devpod` block forwards. Details in the script's own header.
    # NOTE: KeepAlive is on because the agent runs with -D and the script waits
    # on it — process exit means the agent died and the keys must be reloaded.
    ssh-devpod-agent.serviceConfig = {
      ProgramArguments = awaitNix "${sshDevpodAgentScript}/bin/ssh-devpod-agent";
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
      };
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-devpod-agent.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-devpod-agent.log";
    };

    # NOTE: git signs with the `key::` form, which makes ssh-keygen look for the
    # private half in the agent only — nothing else puts it there, so without
    # this every reboot ends in "No private key found for public key" on the
    # first commit.
    ssh-sign-key.serviceConfig = {
      ProgramArguments = awaitNix "${sshSignKeyScript}/bin/ssh-sign-key";
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
      };
      RunAtLoad = true;
      KeepAlive = false;
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-sign-key.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/ssh-sign-key.log";
    };

    # Layout switcher for the BT keyboard; the binary is built by
    # platform/macos/install-bt-layout.sh.
    # NOTE: deliberately NOT a store path. Its TCC permissions (Bluetooth,
    # Accessibility) are bound to the binary's path, so a store path would ask
    # for both again on every rebuild.
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

    # Call summaries from anarlog through `claude -p`. Polled every 15 min
    # instead of watching files — there is no way to know when anarlog finishes
    # writing the transcript, and the delay does not matter.
    # NOTE: deliberately NOT a store path. The script reads prompt.md through
    # Path(__file__).parent, which would point into the store while prompt.md
    # stayed in the repository.
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

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
    };
  };

  # NOTE: reattach is what makes Touch ID work under tmux — there the process is
  # detached from the Aqua session and the prompt never appears at all.
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
    # NOTE: nix daemon settings go here, not into `nix.settings` — that option
    # does not exist with nix.enable = false. Determinate rewrites
    # /etc/nix/nix.conf but includes this file and never touches it.
    etc."nix/nix.custom.conf".text = ''
      # From cpuCores/memoryGiB in flake.nix: ${toString nixMaxJobs} jobs × ${toString nixBuildCores} cores.
      max-jobs = ${toString nixMaxJobs}
      cores = ${toString nixBuildCores}

      # Applies to newly added paths only; `nix store optimise` handles what is
      # already there.
      auto-optimise-store = true

      # Insurance against filling the disk mid-build.
      # NOTE: max-free must be explicit — the default is infinite, so a
      # triggered GC would sweep everything not under a GC root instead of just
      # enough.
      min-free = ${giB 1}
      max-free = ${giB 3}
    '';

    variables = {
      BROWSER = "arc";
      LANG = "en_US.UTF-8";
      LC_ALL = "en_US.UTF-8";
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
    # From flake.nix, so the configuration name and the hostname cannot drift
    # apart on another user.
    hostName = hostname;
    localHostName = hostname;

    # The machine is regularly on foreign networks, where every listening port —
    # a dev server, a kubectl port-forward, restic during a restore — was
    # reachable.
    # NOTE: blockAllIncoming stays false on purpose: blocking everything breaks
    # AirDrop, Handoff and local dev servers reached from the phone.
    applicationFirewall = {
      enable = true;
      blockAllIncoming = false;
      allowSigned = true; # Apple system services
      allowSignedApp = true; # signed third-party (ghostty, orbstack)
      enableStealthMode = true; # invisible to a scanner: no ping, no closed-port probes
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
      # NOTE: an empty list clears pinned apps; commenting the line out instead
      # leaves the dock unmanaged, which is how a fresh machine kept Apple's
      # default set.
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
