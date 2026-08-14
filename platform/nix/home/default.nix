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
    # Пейджер диффа, зовёт его lazygit. Испытательный период с difftastic
    # закончен: синтаксическое сравнение выигрывало на диффах после форматтера,
    # но давало два разных представления одного диффа в панели и в терминале.
    # Ставился императивно через `nix profile install`, то есть вне
    # конфигурации: в образ контейнера не попадал ни разу, и diff там было
    # смотреть нечем.
    delta
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
    # Резолв: в базовом образе нет ни dig, ни host, ни nslookup — при том что
    # скилл ops-net предписывает именно их. За 16 дней одной сессии в cloud-lab
    # 10 промахов `command not found: dig`. Пакет тяжёлый (+32 МБ поверх базы),
    # альтернатива ldns/drill дешевле, но у неё другой синтаксис — модель знает
    # dig, а не drill, и спотыкается ровно в момент диагностики.
    bind.dnsutils
    # Тип по содержимому, а не по расширению: curl приносит HTML с ошибкой
    # вместо архива, и tar ругается на что угодно, кроме настоящей причины.
    file
    # Секреты: sops+age расшифровывают проектные секреты прямо в контейнере,
    # direnv раскладывает их по переменным (use_sops определяется в корневом
    # .envrc самого репозитория — образец в template-devpod).
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
    # CLI той GitOps-системы, на которой стоят кластеры: `flux build` —
    # единственный способ увидеть рендер до пуша. В cloud-lab его не было
    # вообще, в local-lab стоял поставленный руками.
    fluxcd
    # posttooluse-lint.sh:48 зовёт ansible-lint через шеловый PATH. Копия из
    # mason видна только внутри Neovim, поэтому без пакета линт плейбуков молча
    # выключен: функция `run` при отсутствии бинаря делает return 0. Та же
    # причина, по которой yamllint и shellcheck лежат в core.
    ansible-lint
    # terraform validate не видит несуществующих типов инстансов, мёртвых
    # переменных и провайдер-специфичных ошибок.
    tflint
    # Сеть: из образа есть ping, ss, ip — но ничего для пути и портов.
    # mtr — первая команда на «работает через раз», nc — «жив ли порт».
    # mtr работает без привилегий: ping_group_range в контейнере открыт
    # (0 2147483647), ICMP идёт через datagram-сокеты. Отдельный traceroute
    # поэтому не нужен — `mtr -T -P 443` умеет и TCP-пробу.
    mtr
    netcat-gnu
    # Захват требует AF_PACKET, то есть CAP_NET_RAW. Она у контейнера ЕСТЬ
    # (CapBnd=00000000a80425fb), но процессу под uid 1000 не наследуется —
    # значит только `sudo tcpdump` (sudo -n в контейнере работает). Правка
    # runArgs не нужна и ничего бы не изменила: дело не в bounding set.
    # Видно при этом только трафик самого контейнера — свой netns.
    tcpdump
    # Без ambient-привилегий доступен connect-скан (-sT): «какие порты открыты»
    # отвечает честно, SYN-скан — через sudo.
    nmap
    # Пропускная способность честно, включая потери и джиттер по UDP. Замеры
    # curl'ом на 100 КБ меряют разгон TCP, а не потолок канала. Нужен и на
    # второй стороне канала — без этого бесполезен.
    iperf3
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

  # Тот же класс, что man-db выше: home-manager сам тянет glibcLocales и
  # прописывает LOCALE_ARCHIVE в свой environment.d. Полный набор — это ВСЕ
  # локали мира, 223 МБ в образе (замерено `du -sh /nix/store/*glibc-locales*`;
  # цепочка `nix why-depends` идёт через hm_environment.d10homemanager.conf).
  # Контейнер живёт в одной локали — её и объявляем: Dockerfile выставляет
  # LANG/LC_ALL=en_US.UTF-8 и генерирует ровно её же через locale-gen.
  # C.UTF-8 добавлена как fallback: на неё откатываются программы, когда
  # запрошенная локаль недоступна, без неё они сыпали бы предупреждениями.
  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
  };

  home.stateVersion = "26.05";
}
