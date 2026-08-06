{
  pkgs,
  lib,
  profile,
  ...
}:
let
  # --- Core: редактор, шелл, git ---
  corePackages = with pkgs; [
    # Neovim deps
    python313
    nodejs_24
    luarocks # нужен mason'у (luacheck); свой lua тащит с собой
    tree-sitter
    # CLI
    eza
    fd
    jq # statusline.sh парсит им payload — без jq строка пустая
    ripgrep
    starship
    neovim
    tmux
    atuin
    fzf # интерактивный выбор для kubectx/kubens и claude/custom/setup.sh
    tmuxPlugins.tmux-thumbs # flash-метки по экрану (prefix+f), nix-сборка без cargo
    btop
    lazygit
    uv
    # НЕ мёртвый вес, хоть руками ни разу не вызывались: gitleaks сканирует
    # git diff --cached в tools/git/hooks/pre-commit/pre-push (симлинк
    # ~/.git-hooks, ставится в контейнере тоже через files.nix) и жёстко
    # валит commit/push при отсутствии бинаря — это не soft-skip.
    gitleaks
    # НЕ дубль mason: mason кладёт свои копии в ~/.local/share/nvim/mason/bin,
    # который добавлен в PATH только внутри Neovim, а не в шелл. Claude Code
    # PostToolUse hook (tools/claude/hooks/posttooluse-lint.sh) ищет yamllint
    # и shellcheck через обычный command -v по шеловому PATH — без них
    # линт .sh/.yaml тихо перестаёт работать во всех проектах в контейнере.
    yamllint
    shellcheck
    gh
    glab
    # Секреты: sops+age расшифровывают проектные секреты прямо в контейнере,
    # direnv раскладывает их по переменным (use_sops в tools/direnv/direnvrc).
    # rbw сюда НЕ ставится сознательно: Bitwarden живёт только на маке, а в
    # контейнер приезжает единственный age-ключ зоны (доставка — conf.d/devpod.zsh).
    # Мастер-пароль от vault на удалённом docker-хосте, где root есть не только
    # у меня, не должен оказываться в принципе.
    direnv
    nix-direnv
    sops
    age
  ];

  # --- DevOps: core + IaC/K8s/container tools ---
  devopsPackages = with pkgs; [
    # НЕ мёртвый вес, хоть go.mod в рабочих репозиториях нет: mason ставит
    # jsonnet-language-server через `go install`, и это единственный способ
    # его доставить (home/hooks.nix:9-10,102-109 — без go на devops-профиле
    # доустановка молча падала с "Could not find executable go in PATH").
    go
    terraform
    ansible
    kubectl
    kubernetes-helm
    kubectx # переключение context/namespace (kubectx/kubens, с fzf — интерактивно)
    talosctl # управление Talos Linux кластерами (local-lab: talos на Proxmox)
    k9s
    argocd # argocd GitOps (плагин k9s, local-lab на ArgoCD)
    yq-go
  ];
in
{
  imports = [
    ./files.nix # симлинки dotfiles (бывшие links=() из install.sh)
    ./hooks.nix # императивные установщики (claude, ccusage, zinit, …)
  ];

  home.packages = corePackages ++ lib.optionals (profile == "devops") devopsPackages;

  # CLI home-manager в профиле — для повторных switch (install.sh, cron)
  programs.home-manager.enable = true;

  # "There are 372 unread and relevant news items" в конце каждой активации —
  # это ченджлог опций home-manager. Читается через `home-manager news`, но
  # счётчик копится с первой установки и к нашему конфигу отношения не имеет:
  # в свежем контейнере он тот же самый. Молчим, чтобы не тонула сводка warn'ов.
  news.display = "silent";

  # Мануал home-manager: `man home-configuration.nix`. Не пользуемся, а собирать
  # его дорого — он тянет прогон nixosOptionsDoc по всем опциям HM и деривейшн
  # options.json на КАЖДОМ switch (видно в логе активации).
  # Он же источник ворнинга «builtins.derivation ... options.json ... without a
  # proper context»: документация подставляет путь nixpkgs строкой без контекста
  # (docs/default.nix, там же TODO про негибкость nixosOptionsDoc).
  # Ключ именно manpages: manual.json.enable и html.enable по умолчанию уже
  # false, выключать их смысла нет — проверено, drvPath не меняется.
  manual.manpages.enable = false;

  # Отдельная опция от manual.manpages выше: programs.man по умолчанию сам
  # добавляет man-db (~75 МБ замыкания: mandb, apropos, whatis, catman, …) в
  # home.packages — не пакет из наших списков, а дефолт модуля home-manager.
  # man в контейнере не читают, страницы никто не открывает.
  programs.man.enable = false;

  home.stateVersion = "26.05";
}
