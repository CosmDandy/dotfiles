{
  config,
  lib,
  pkgs,
  piTools,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  # Keep private skill bodies private. This allowlist deliberately excludes personal
  # journals, time tracking, Claude history, and project knowledge bases.
  skills = [
    "commit"
    "compliance"
    "ops-metal"
    "ops-net"
    "ops-remote"
    "ops-vm"
    "performance"
    "skill-tester"
    "spec"
    "ux"
  ];
  skillFiles = lib.genAttrs (map (name: ".pi/agent/skills/${name}") skills) (path: {
    source = link "tools/claude/custom/skills/${baseNameOf path}";
  });
in
{
  home.packages = [
    piTools.agent
    piTools.statusline
  ];

  home.file = {
    # Replace the managed-installer shim, which otherwise shadows the Nix package.
    ".local/bin/pi".source = "${piTools.agent}/bin/pi";
    ".pi/agent/CLAUDE.md".source = link "tools/claude/CLAUDE.md";
    ".pi/agent/APPEND_SYSTEM.md".source = link "tools/pi/APPEND_SYSTEM.md";
    ".pi/agent/extensions/solarized-status.ts".source = link "tools/pi/extensions/solarized-status.ts";
    ".pi/agent/extensions/compact-tools.ts".source = link "tools/pi/extensions/compact-tools.ts";
    ".pi/agent/themes/solarized-dark.json".source = link "tools/pi/themes/solarized-dark.json";
    ".pi/agent/themes/solarized-light.json".source = link "tools/pi/themes/solarized-light.json";
    ".pi/agent/claude-rules".source = link "tools/claude/custom/rules";
    ".pi/agent/bin/solarized-statusline".source = "${piTools.statusline}/bin/pi-statusline";
  }
  // skillFiles;

  # Pi rewrites settings, so seed only a missing file; never symlink mutable state
  # or overwrite a user's provider, models, MCP credentials, or resource choices.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    # Remove only legacy Pi links, never Claude's skills or independent user files.
    for name in c-brag c-call c-daylog c-log knowledge lab; do
      path="$HOME/.pi/agent/skills/$name"
      if [ -L "$path" ]; then
        target="$(${pkgs.coreutils}/bin/readlink "$path")"
        case "$target" in
          "$HOME/.claude/skills/$name"|"${dotfiles}/tools/claude/custom/skills/$name")
            run ${pkgs.coreutils}/bin/rm "$path"
            ;;
        esac
      fi
    done
    if [ ! -e "$HOME/.pi/agent/settings.json" ]; then
      run ${pkgs.coreutils}/bin/install -m 0600 \
        "${dotfiles}/tools/pi/settings.json" "$HOME/.pi/agent/settings.json"
    fi
  '';
}
