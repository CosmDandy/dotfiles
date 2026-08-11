{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Живой working copy репо: на Linux devpod клонирует в ~/dotfiles
  # (~/.dotfiles — bridge-симлинк), на macOS репо живёт в ~/.dotfiles
  dotfiles = "${config.home.homeDirectory}/${
    if pkgs.stdenv.isDarwin then ".dotfiles" else "dotfiles"
  }";
  # Симлинк на файл в клоне, НЕ на копию в store: правка в репо видна сразу,
  # без home-manager switch (та же семантика, что были ln -s в install.sh)
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  home.file = {
    ".tmux.conf".source = link "tools/tmux/.tmux.conf";
    ".zprofile".source = link "tools/zsh/.zprofile";
    ".zshrc".source = link "tools/zsh/.zshrc";
    ".zsh/completions".source = link "tools/zsh/completions";
    ".gitignore_global".source = link "tools/git/.gitignore_global";
    ".gitconfig".source = link "tools/git/.gitconfig";
    ".allowed_signers".source = link "tools/git/.allowed_signers";
    ".git-hooks".source = link "tools/git/hooks";
    ".claude/CLAUDE.md".source = link "tools/claude/CLAUDE.md";
    ".claude/settings.json".source = link "tools/claude/settings.json";
    ".claude/statusline.sh".source = link "tools/claude/statusline.sh";
    ".claude/keybindings.json".source = link "tools/claude/keybindings.json";
    # ~/.claude/{agents,commands,skills,rules} НЕ здесь: ими владеет
    # tools/claude/custom/install.sh (хук installClaudeCustom) — сабмодуль
    # может отсутствовать на момент linkGeneration
  };

  xdg.configFile = {
    # Рабочие идентичности — из сабмодуля private/, каталогом целиком: домены
    # работодателей не место в публичном репозитории, а новый <имя>.conf должен
    # подхватываться без правки этого списка. ~/.gitconfig делает безусловный
    # include ~/.config/git-identities/includes.conf, а условия по URL remote —
    # уже внутри. Каталог отдельный, а НЕ ~/.config/git: там лежит собственный
    # `ignore`, и симлинк на весь каталог его бы снёс. Плюс git читает
    # ~/.config/git/config как второй глобальный конфиг — лишний риск.
    "git-identities".source = link "private/git";
    # Общий для обеих платформ: use_sops нужен и на маке, и в dev-контейнере
    "direnv/direnvrc".source = link "tools/direnv/direnvrc";
    "lazygit/config.yml".source = link "tools/lazygit/config.yml";
    "lazygit/theme-light.yml".source = link "tools/lazygit/theme-light.yml";
    "lazygit/theme-dark.yml".source = link "tools/lazygit/theme-dark.yml";
    "starship.toml".source = link "tools/starship/starship.toml";
    "atuin/config.toml".source = link "tools/atuin/config.toml";
    "nvim".source = link "tools/nvim";
    "btop/btop.conf".source = link "tools/btop/btop.conf";
    # k9s НЕ одним симлинком на весь tools/k9s (как остальные каталоги выше):
    # k9s.zsh переключает активный скин, перезаписывая symlink
    # ~/.config/k9s/skins/solarized.yaml на -dark/-light. Если бы ~/.config/k9s
    # целиком был симлинком в репозиторий, эта перезапись летела бы прямо в
    # working copy (мутабельный артефакт «из nix в исходники», дерево вечно
    # dirty). Линкуем файлы поштучно — home-manager тогда создаёт РЕАЛЬНЫЙ
    # каталог ~/.config/k9s/skins с симлинками на статичные skin-файлы репо,
    # а solarized.yaml внутри него — обычная запись на реальной файловой
    # системе, вне репозитория.
    "k9s/config.yaml".source = link "tools/k9s/config.yaml";
    "k9s/aliases.yaml".source = link "tools/k9s/aliases.yaml";
    "k9s/hotkeys.yaml".source = link "tools/k9s/hotkeys.yaml";
    "k9s/plugins.yaml".source = link "tools/k9s/plugins.yaml";
    "k9s/views.yaml".source = link "tools/k9s/views.yaml";
    "k9s/skins/solarized-dark.yaml".source = link "tools/k9s/skins/solarized-dark.yaml";
    "k9s/skins/solarized-light.yaml".source = link "tools/k9s/skins/solarized-light.yaml";
  };

  home.activation = {
    # Каталоги под runtime-данные (kube/talos конфиги приносятся руками)
    dotfilesDirs = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run mkdir -p "$HOME/.kube/configs" "$HOME/.talos"
    '';

    # Активный скин k9s — мутабельный симлинк (обёртка k9s.zsh переключает
    # dark/light по теме), поэтому не home.file: только дефолт, если отсутствует.
    # Каталог реальный (см. xdg.configFile."k9s/skins/..." выше), а не симлинк
    # в репозиторий — здесь можно писать, не трогая working copy.
    k9sDefaultSkin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      skinDir="${config.xdg.configHome}/k9s/skins"
      if [ -d "$skinDir" ] && [ ! -e "$skinDir/solarized.yaml" ]; then
        run ln -sf solarized-dark.yaml "$skinDir/solarized.yaml"
      fi
    '';
  };
  # known_hosts не раскладывается вовсе (файл удалён из репозитория 2026-08-06).
  # Он копился годами и стал картой всей инфраструктуры, куда когда-либо ходили,
  # включая рабочий GitLab с нестандартным портом — в публичном репозитории это
  # готовая цель для разведки, а пользы почти нет: ssh дописывает хосты сам при
  # первом подключении, TOFU-подтверждение делается один раз на хост.
}
