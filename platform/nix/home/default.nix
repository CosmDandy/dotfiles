{
  pkgs,
  lib,
  profile,
  ...
}:
let
  # --- Core: editor, shell, git ---
  corePackages = with pkgs; [
    # Neovim deps
    python313
    nodejs_24
    luarocks # for mason (luacheck); brings its own lua
    tree-sitter
    # CLI
    eza
    fd
    jq # statusline.sh parses the payload with it — without jq the line is empty
    ripgrep
    starship
    neovim
    tmux
    atuin
    fzf # interactive pickers for kubectx/kubens and claude/custom/setup.sh
    tmuxPlugins.tmux-thumbs # prefix+f labels; the nix build needs no cargo
    btop
    lazygit
    delta # diff renderer called by lazygit
    uv
    # NOTE: not dead weight despite never being called by hand — the pre-commit
    # and pre-push hooks run gitleaks and fail hard without the binary, by
    # design.
    gitleaks
    # NOTE: not duplicates of mason. mason's copies live in a directory that is
    # on PATH only inside Neovim, while posttooluse-lint.sh looks them up with a
    # plain `command -v` — without these, linting .sh/.yaml silently stops in
    # every project.
    yamllint
    shellcheck
    gh
    glab
    # NOTE: the base image has neither dig nor host nor nslookup, while the
    # ops-net skill prescribes exactly those — 10 `command not found: dig` in 16
    # days of one session. ldns/drill is cheaper but has a different syntax, and
    # the model knows dig.
    bind.dnsutils
    # type by content, not extension: curl brings back an HTML error page
    # instead of an archive, and tar then complains about anything but the real
    # cause
    file
    # Secrets: sops+age decrypt project secrets in the container, direnv spreads
    # them into variables (use_sops is defined in the repository's own root
    # .envrc).
    # NOTE: rbw is deliberately absent — the vault master password must never
    # reach a remote docker host where root is not only mine. Containers get a
    # single age key for the zone instead (delivered by conf.d/devpod.zsh).
    direnv
    nix-direnv
    sops
    age
  ];

  # --- DevOps: core + IaC/K8s/container tools ---
  devopsPackages = with pkgs; [
    # Go and its toolchain. The original reason stands: mason installs
    # jsonnet-language-server via `go install`, and without go in the profile
    # that step failed silently with "Could not find executable go in PATH"
    # (home/hooks.nix:9-10,102-109). It is no longer the only reason — Go is
    # now a language written here, not just a build dependency.
    #
    # The tools come from nixpkgs rather than mason on purpose: mason builds Go
    # packages with that same `go install`, compiling each one at install time
    # (minutes for gopls alone) and repeating the work in every container.
    # nixpkgs ships them prebuilt and pinned by flake.lock.
    #   gotools       -> goimports (conform runs it before gofumpt)
    #   delve         -> dlv, the debugger nvim-dap-go drives
    #   golangci-lint -> aggregate linter, includes staticcheck
    go
    gopls
    gotools
    gofumpt
    delve
    golangci-lint
    terraform
    ansible
    kubectl
    kubernetes-helm
    kubectx
    talosctl # local-lab runs Talos on Proxmox
    k9s
    argocd
    yq-go
    # `flux build` is the only way to see the render before pushing.
    fluxcd
    # NOTE: posttooluse-lint.sh calls it through the shell PATH, where mason's
    # copy is invisible — without the package, playbook linting is silently off,
    # because the helper returns 0 when the binary is missing.
    ansible-lint
    # terraform validate does not see non-existent instance types, dead
    # variables or provider-specific errors
    tflint
    # The image has ping, ss and ip but nothing for the path or for ports.
    # NOTE: mtr needs no privileges — ping_group_range is open in the container
    # and ICMP goes over datagram sockets. It also covers traceroute: `mtr -T -P
    # 443` does TCP.
    mtr
    netcat-gnu
    # NOTE: capture needs CAP_NET_RAW, which the container HAS in its bounding
    # set but does not inherit to a uid-1000 process — so it is `sudo tcpdump`
    # only (sudo -n works there). Changing runArgs would not help: the bounding
    # set is not the problem. Only the container's own netns is visible.
    tcpdump
    # A connect scan (-sT) works without ambient privileges; SYN scan needs
    # sudo.
    nmap
    # NOTE: needed on both ends of the link to be of any use. Measuring with
    # curl over 100 KB measures TCP ramp-up, not the ceiling.
    iperf3
  ];
in
{
  imports = [
    ./files.nix # dotfiles symlinks
    ./hooks.nix # imperative installers (claude, zinit, …)
  ];

  # NOTE: a C compiler is required at runtime, not only during activation —
  # nvim-treesitter compiles every parser with `cc` and mason builds luacheck's
  # luafilesystem. Linux only: on darwin clang comes from the Command Line
  # Tools, and a nix gcc ahead of it in PATH would break the system toolchain.
  # Caught on an OrbStack ubuntu-minimal machine, where /usr/bin has no cc and
  # all ~40 parsers failed with "No such file or directory".
  home.packages =
    corePackages
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.gcc ]
    ++ lib.optionals (profile == "devops") devopsPackages;

  # the home-manager CLI in the profile, for repeat switches from install.sh and
  # cron
  programs.home-manager.enable = true;

  # NOTE: the "N unread news items" counter accumulates from the first install
  # and has nothing to do with this config — it only drowns the warning summary.
  news.display = "silent";

  # NOTE: manpages is the key that matters — it drags a nixosOptionsDoc run over
  # every HM option and an options.json derivation into EVERY switch, and is the
  # source of the contextless `builtins.derivation` warning. manual.json/html
  # are false by default, so disabling them changes nothing (verified by
  # drvPath).
  manual.manpages.enable = false;

  # NOTE: a separate thing from manual.manpages — programs.man defaults to
  # pulling man-db (~75 MB of closure) into home.packages by itself.
  programs.man.enable = false;

  # NOTE: same class again — home-manager pulls glibcLocales and sets
  # LOCALE_ARCHIVE in its own environment.d. The full set is every locale in the
  # world, 223 MB in the image, while the container lives in the one the
  # Dockerfile generates. C.UTF-8 is the fallback programs drop to when the
  # requested locale is unavailable.
  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
  };

  home.stateVersion = "26.05";
}
