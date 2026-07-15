{ config, lib, ... }:
let
  # Живой working copy репо (devpod клонирует в ~/dotfiles; ~/.dotfiles — bridge-симлинк)
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  # Симлинк на файл в клоне, НЕ на копию в store: правка в репо видна сразу,
  # без home-manager switch (та же семантика, что были ln -s в install.sh)
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in {
  home.file = {
    ".tmux.conf".source = link "tools/tmux/.tmux.conf";
    ".zprofile".source = link "tools/zsh/.zprofile";
    ".zshrc".source = link "tools/zsh/.zshrc";
    ".zsh/completions".source = link "tools/zsh/completions";
    ".gitignore_global".source = link "tools/git/.gitignore_global";
    ".gitconfig".source = link "tools/git/.gitconfig";
    ".gitconfig-work".source = link "tools/git/.gitconfig-work";
    ".allowed_signers".source = link "tools/git/.allowed_signers";
    ".git-hooks".source = link "tools/git/hooks";
    ".claude/CLAUDE.md".source = link "tools/claude/CLAUDE.md";
    ".claude/settings.json".source = link "tools/claude/settings.json";
    ".claude/statusline.sh".source = link "tools/claude/statusline.sh";
    ".claude/agents".source = link "tools/claude/agents";
    ".claude/commands".source = link "tools/claude/commands";
    ".claude/skills".source = link "tools/claude/skills";
    ".claude/rules".source = link "tools/claude/rules";
    ".lnav/configs/default/config.json".source = link "tools/lnav/config.json";
  };

  xdg.configFile = {
    "lazygit/config.yml".source = link "tools/lazygit/config.yml";
    "lazygit/theme-light.yml".source = link "tools/lazygit/theme-light.yml";
    "lazygit/theme-dark.yml".source = link "tools/lazygit/theme-dark.yml";
    "starship.toml".source = link "tools/starship/starship.toml";
    "atuin/config.toml".source = link "tools/atuin/config.toml";
    "nvim".source = link "tools/nvim";
    "btop/btop.conf".source = link "tools/btop/btop.conf";
    "k9s".source = link "tools/k9s";
  };

  home.activation = {
    # Каталоги под runtime-данные (kube/talos конфиги приносятся руками)
    dotfilesDirs = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run mkdir -p "$HOME/.kube/configs" "$HOME/.talos"
    '';

    # known_hosts — копией, не симлинком: ssh должен мочь дописывать в файл.
    # Guard на клон: при сборке образа ~/dotfiles ещё нет
    sshKnownHosts = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -f "${dotfiles}/tools/git/known_hosts" ]; then
        run mkdir -p "$HOME/.ssh"
        run cp "${dotfiles}/tools/git/known_hosts" "$HOME/.ssh/known_hosts"
        run chmod 644 "$HOME/.ssh/known_hosts"
      fi
    '';

    # Активный скин k9s — мутабельный симлинк (обёртка k9s.zsh переключает
    # dark/light по теме), поэтому не home.file: только дефолт, если отсутствует
    k9sDefaultSkin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -d "${dotfiles}/tools/k9s/skins" ] && [ ! -e "${dotfiles}/tools/k9s/skins/solarized.yaml" ]; then
        run ln -sf solarized-dark.yaml "${dotfiles}/tools/k9s/skins/solarized.yaml"
      fi
    '';
  };
}
