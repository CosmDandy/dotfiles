{ pkgs, lib, profile, ... }:
let
  # --- Core: редактор, шелл, git ---
  corePackages = with pkgs; [
    # Neovim deps
    python313
    nodejs_24
    luarocks  # нужен mason'у (luacheck); свой lua тащит с собой
    tree-sitter
    # CLI
    eza
    fd
    ripgrep
    starship
    neovim
    tmux
    atuin
    fzf            # интерактивный выбор для kubectx/kubens и claude/custom/setup.sh
    tmuxPlugins.tmux-thumbs   # flash-метки по экрану (prefix+f), nix-сборка без cargo
    btop
    lazygit
    lazydocker
    uv
    gitleaks
    yamllint
    shellcheck
    gh
    glab
    iperf3
  ];

  # --- DevOps: core + IaC/K8s/container tools ---
  devopsPackages = with pkgs; [
    go
    terraform
    ansible
    kubectl
    kubernetes-helm
    kubectx        # переключение context/namespace (kubectx/kubens, с fzf — интерактивно)
    talosctl       # управление Talos Linux кластерами (local-lab: talos на Proxmox)
    k9s
    dive           # анализ слоёв образа (и плагин k9s)
    argocd         # argocd GitOps (плагин k9s, local-lab на ArgoCD)
    yq-go
  ];
in {
  imports = [
    ./files.nix   # симлинки dotfiles (бывшие links=() из install.sh)
    ./hooks.nix   # императивные установщики (claude, ccusage, zinit, …)
  ];

  home.packages = corePackages ++ lib.optionals (profile == "devops") devopsPackages;

  # CLI home-manager в профиле — для повторных switch (install.sh, cron)
  programs.home-manager.enable = true;

  # "There are 372 unread and relevant news items" в конце каждой активации —
  # это ченджлог опций home-manager. Читается через `home-manager news`, но
  # счётчик копится с первой установки и к нашему конфигу отношения не имеет:
  # в свежем контейнере он тот же самый. Молчим, чтобы не тонула сводка warn'ов.
  news.display = "silent";

  home.stateVersion = "26.05";
}
