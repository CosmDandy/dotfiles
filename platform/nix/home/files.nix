{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The live working copy: devpod clones into ~/dotfiles on Linux, while on macOS the
  # repo lives in ~/.dotfiles.
  dotfiles = "${config.home.homeDirectory}/${
    if pkgs.stdenv.hostPlatform.isDarwin then ".dotfiles" else "dotfiles"
  }";
  # NOTE: a symlink to the file in the clone, NOT a copy in the store — an edit in the
  # repo takes effect without a home-manager switch. Keep it that way.
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
in
{
  home.file = {
    ".tmux.conf".source = link "tools/tmux/.tmux.conf";
    # NOTE: .zshenv is read before every other rc file, which is the only place
    # a system-wide compinit can be stopped — see the file itself for the
    # numbers that made it necessary.
    ".zshenv".source = link "tools/zsh/.zshenv";
    ".zprofile".source = link "tools/zsh/.zprofile";
    ".zshrc".source = link "tools/zsh/.zshrc";
    ".zsh/completions".source = link "tools/zsh/completions";
    ".gitignore_global".source = link "tools/git/.gitignore_global";
    ".gitconfig".source = link "tools/git/.gitconfig";
    ".allowed_signers".source = link "tools/git/.allowed_signers";
    # NOTE: ssh configs are NOT here and must not be — they are macOS-only and live in
    # darwin.nix. Bringing them into containers was tried and cost dearly: Linux ssh
    # aborts entirely on macOS-only options (UseKeychain) and on algorithms newer than
    # its version, and patching each incompatibility broke either macOS or the container.
    ".git-hooks".source = link "tools/git/hooks";
    ".claude/CLAUDE.md".source = link "tools/claude/CLAUDE.md";
    ".claude/settings.json".source = link "tools/claude/settings.json";
    ".claude/statusline.sh".source = link "tools/claude/statusline.sh";
    ".claude/keybindings.json".source = link "tools/claude/keybindings.json";
    # NOTE: ~/.claude/{agents,commands,skills,rules} are not here — the custom submodule
    # owns them, and it may be absent at linkGeneration time.
  };

  xdg.configFile = {
    # Work identities come from the private submodule, as a whole directory: employer
    # domains do not belong in a public repo, and a new <name>.conf must be picked up
    # without editing this list.
    # NOTE: a separate directory, NOT ~/.config/git — that already holds its own `ignore`
    # which a whole-directory symlink would wipe, and git reads ~/.config/git/config as a
    # second global config.
    "git-identities".source = link "private/git";
    # Shared by both platforms: it wires up nix-direnv, which is needed in the container
    # too. Project-specific functions deliberately live in the repository's own .envrc.
    "direnv/direnvrc".source = link "tools/direnv/direnvrc";
    "lazygit/config.yml".source = link "tools/lazygit/config.yml";
    "lazygit/theme-light.yml".source = link "tools/lazygit/theme-light.yml";
    "lazygit/theme-dark.yml".source = link "tools/lazygit/theme-dark.yml";
    "starship.toml".source = link "tools/starship/starship.toml";
    "atuin/config.toml".source = link "tools/atuin/config.toml";
    "nvim".source = link "tools/nvim";
    # Fallback rule set for projects without a ruff config of their own; conform and
    # nvim-lint both run plain ruff, so both read it.
    "ruff/ruff.toml".source = link "tools/ruff/ruff.toml";
    # Same idea for yamllint: used only where the project has no .yamllint.
    "yamllint/config".source = link "tools/yamllint/config";
    "btop/btop.conf".source = link "tools/btop/btop.conf";
    # NOTE: k9s is linked file by file rather than as one directory — k9s.zsh switches the
    # active skin by rewriting ~/.config/k9s/skins/solarized.yaml. With the whole directory
    # symlinked into the repo that write would land in the working copy and leave the tree
    # permanently dirty. Per-file linking makes home-manager create a REAL skins directory.
    "k9s/config.yaml".source = link "tools/k9s/config.yaml";
    "k9s/aliases.yaml".source = link "tools/k9s/aliases.yaml";
    "k9s/hotkeys.yaml".source = link "tools/k9s/hotkeys.yaml";
    "k9s/plugins.yaml".source = link "tools/k9s/plugins.yaml";
    "k9s/views.yaml".source = link "tools/k9s/views.yaml";
    "k9s/skins/solarized-dark.yaml".source = link "tools/k9s/skins/solarized-dark.yaml";
    "k9s/skins/solarized-light.yaml".source = link "tools/k9s/skins/solarized-light.yaml";
  };

  home.activation = {
    # runtime data directories (kube/talos configs are brought in by hand)
    dotfilesDirs = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run mkdir -p "$HOME/.kube/configs" "$HOME/.talos"
    '';

    # The active k9s skin is a mutable symlink the k9s.zsh wrapper flips by theme, so it
    # cannot be home.file — only a default when missing.
    k9sDefaultSkin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      skinDir="${config.xdg.configHome}/k9s/skins"
      if [ -d "$skinDir" ] && [ ! -e "$skinDir/solarized.yaml" ]; then
        run ln -sf solarized-dark.yaml "$skinDir/solarized.yaml"
      fi
    '';
  };
  # NOTE: known_hosts is deliberately not deployed at all. It accumulated for years into a
  # map of every host ever reached, including a work GitLab on a non-standard port — in a
  # public repository that is reconnaissance material, and ssh appends hosts by itself.
}
