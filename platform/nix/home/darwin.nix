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
  # NOTE: hooks whose warnings must reach the summary have to run BEFORE it, and
  # entryAfter is not enough — reportWarnings is declared in hooks.nix, which is
  # shared with Linux and cannot name macOS-only hooks.
  beforeReport = lib.hm.dag.entryBetween [ "reportWarnings" ] [ "linkGeneration" ];
  w = import ./warn.nix { inherit config; };
  warn = w.mk;
  # NOTE: the activation PATH is minimal — brew binaries are found explicitly,
  # and zsh is needed for apply.sh's `env zsh` shebang: it exists in /bin, but
  # /bin is not on that PATH and the hook died with "env: zsh: No such file or
  # directory".
  hookPath = "/opt/homebrew/bin:/usr/local/bin:${
    lib.makeBinPath [
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.zsh
    ]
  }";
in
{
  imports = [
    ./files.nix
    ./hooks.nix
  ];

  # NOTE: duplicated from default.nix, which the mac does not import — without
  # it the HM manual is built on every darwin-rebuild.
  manual.manpages.enable = false;

  home.stateVersion = "26.05";

  home.file = {
    ".hushlogin".source = link "tools/zsh/.hushlogin";
    # NOTE: .aerospace.toml and Leader Key's config.json are NOT here — login
    # items read them before /nix is mounted; see the loginItemConfigs hook
    # below.
    # NOTE: known_hosts is not here either — ssh recreates the file and destroys
    # the symlink, so every following switch would hit a backup.
    # NOTE: ssh configs are macOS-only. They are deliberately not shipped into
    # containers, where ssh is needed only to reach forges over the forwarded
    # agent — it was tried, and Linux ssh 9.6 aborts entirely ("terminating, N
    # bad configuration options") on UseKeychain and mlkem768x25519, taking git
    # down with it.
    ".ssh/config".source = link "private/ssh/config";
    # the whole directory, so a new file is picked up by the Include glob
    # without editing this list
    ".ssh/config.d".source = link "private/ssh/config.d";
    # NOTE: rbw ignores XDG_CONFIG_HOME on macOS and reads its config from
    # Library.
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
    # direnvrc lives in files.nix — nix-direnv is needed in the dev container
    # too
  };

  home.activation = {
    # NOTE: login-item configs are DIRECT symlinks, not home.file. /nix is a
    # separate encrypted volume that cannot be mounted before the user unlocks
    # at login: measured 2026-08-16, the first mount attempt fails at 12:40:20,
    # AeroSpace and Leader Key start at 12:40:40, and the volume is mounted only
    # at 12:40:51. For those eleven seconds a symlink through /nix/store dangles
    # and the app silently falls back to its default config — the whole
    # explanation for the endless "reload config" in AeroSpace.
    loginItemConfigs = after ''
      run ln -sfn "${dotfiles}/tools/aerospace/.aerospace.toml" \
        "$HOME/.aerospace.toml"
      run mkdir -p "$HOME/Library/Application Support/Leader Key"
      run ln -sfn "${dotfiles}/tools/leader-key/config.json" \
        "$HOME/Library/Application Support/Leader Key/config.json"
    '';

    # NOTE: trust.json is a direct symlink too — brew writes into the trust
    # store and refuses a target in /nix/store ("insecure trust store: target
    # directory not owned by the current user"), which fails brew bundle inside
    # the activation. Both paths are needed: ~/.config/homebrew for an
    # interactive shell, ~/.homebrew for brew bundle under darwin-rebuild, where
    # sudo keeps only PATH.
    homebrewTrust = after ''
      run mkdir -p "$HOME/.homebrew" "$HOME/.config/homebrew"
      run ln -sfn "${dotfiles}/tools/homebrew/trust.json" "$HOME/.homebrew/trust.json"
      run ln -sfn "${dotfiles}/tools/homebrew/trust.json" "$HOME/.config/homebrew/trust.json"
    '';

    # ControlMaster in private/ssh/config keeps its multiplex sockets here.
    # macOS only — containers get no ssh config and no multiplexing.
    sshSockets = after ''
      run mkdir -p "$HOME/.ssh/sockets"
    '';

    # NOTE: the Graphite layout is COPIED, not symlinked — Text Input Sources
    # does not accept symlinked bundles, and a /nix/store target is not owned by
    # the user either. Not cosmetic: bt-layout.conf references that input
    # source, and without the installed bundle the daemon cannot call
    # TISEnableInputSource, so switching on keyboard connect stops working. The
    # source lives in the assets submodule, which may be absent.
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

    # devpod is installed by the homebrew step of nix-darwin's activation, which
    # runs BEFORE home-manager's, so the binary already exists on the first
    # pass. apply.sh skips everything without the devpod CLI and does not treat
    # an unreachable ssh provider as a failure.
    setupDevpod = beforeReport ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/devpod/apply.sh" \
        || ${warn "devpod apply failed"}
    '';

    # apply.sh skips everything without the orb CLI (a fresh machine where
    # OrbStack has never started, or a VM without nested virtualisation).
    applyOrbstack = beforeReport ''
      PATH="${hookPath}:$PATH" run "${dotfiles}/tools/orbstack/apply.sh" \
        || ${warn "orbstack apply failed"}
    '';
  };
}
