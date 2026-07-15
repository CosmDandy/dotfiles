{ pkgs, lib, profile, ... }:
let
  # --- Base: core editor, shell, git ---
  basePackages = with pkgs; [
    # Neovim deps
    python313
    nodejs_24
    lua
    luarocks
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

  # --- Full: base + IaC/K8s/container/DevOps tools ---
  fullPackages = with pkgs; [
    go
    gdu
    terraform
    ansible
    kubectl
    kubernetes-helm
    kubectx        # переключение context/namespace (kubectx/kubens, с fzf — интерактивно)
    talosctl       # управление Talos Linux кластерами
    k9s
    dive
    stern          # мультипод-логи (плагин k9s)
    kubectl-neat   # чистый YAML (плагин k9s)
    fluxcd         # flux GitOps (плагин k9s)
    argocd         # argocd GitOps (плагин k9s)
    trivy          # скан образов (плагин k9s)
    lnav
    yq-go
  ];
in {
  imports = [
    ./files.nix   # симлинки dotfiles (бывшие links=() из install.sh)
    ./hooks.nix   # императивные установщики (claude, ccusage, tpm, zinit, …)
  ];

  home.packages = basePackages ++ lib.optionals (profile == "full") fullPackages;

  # CLI home-manager в профиле — для повторных switch (install.sh, cron)
  programs.home-manager.enable = true;

  home.stateVersion = "26.05";
}
