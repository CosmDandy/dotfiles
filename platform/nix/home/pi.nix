{
  config,
  lib,
  pkgs,
  piTools,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/${
    if pkgs.stdenv.hostPlatform.isDarwin then ".dotfiles" else "dotfiles"
  }";
  link = path: config.lib.file.mkOutOfStoreSymlink "${dotfiles}/${path}";
  skills = [
    "ops-metal"
    "ops-net"
    "ops-remote"
    "ops-vm"
  ];
  skillFiles = lib.genAttrs (map (name: ".pi/agent/skills/${name}") skills) (path: {
    source = link "tools/pi/skills/${baseNameOf path}";
  });
  mcpPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.jq
  ];
in
{
  home.packages = lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) [
    piTools.agent
    piTools.statusline
  ];

  home.file = {
    # Replace the managed-installer shim, which otherwise shadows the Nix package.
    ".local/bin/pi".source = "${piTools.agent}/bin/pi";
    ".pi/agent/AGENTS.md".source = link "tools/pi/AGENTS.md";
    ".pi/agent/keybindings.json".source = link "tools/pi/keybindings.json";
    ".pi/agent/extensions/solarized-status.ts".source = link "tools/pi/extensions/solarized-status.ts";
    ".pi/agent/extensions/compaction.ts".source = link "tools/pi/extensions/compaction.ts";
    ".pi/agent/extensions/compact-tools.ts".source = link "tools/pi/extensions/compact-tools.ts";
    ".pi/agent/extensions/work-mode.ts".source = link "tools/pi/extensions/work-mode.ts";
    ".pi/agent/extensions/codex-web-search.ts".source = link "tools/pi/extensions/codex-web-search.ts";
    ".pi/agent/extensions/session-auto-title.ts".source =
      link "tools/pi/extensions/session-auto-title.ts";
    ".pi/agent/prompts/commit.md".source = link "tools/pi/prompts/commit.md";
    ".pi/agent/prompts/recap.md".source = link "tools/pi/prompts/recap.md";
    ".pi/agent/themes/solarized-dark.json".source = link "tools/pi/themes/solarized-dark.json";
    ".pi/agent/themes/solarized-light.json".source = link "tools/pi/themes/solarized-light.json";
    ".pi/agent/bin/solarized-statusline".source = "${piTools.statusline}/bin/pi-statusline";
  }
  // skillFiles;

  home.activation.piMcp = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/env PATH=${mcpPath} \
      ${pkgs.bash}/bin/bash "${dotfiles}/tools/pi/install-mcp.sh" \
      "${dotfiles}/tools/pi/mcp.json" "$HOME/.pi/agent/mcp.json"
  '';

  home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    # Remove only legacy Pi links, never Claude's skills or independent user files.
    for name in commit compliance performance skill-tester spec ux c-brag c-call c-daylog c-log knowledge lab; do
      path="$HOME/.pi/agent/skills/$name"
      if [ -L "$path" ]; then
        target="$(${pkgs.coreutils}/bin/readlink "$path")"
        case "$target" in
          "$HOME/.claude/skills/$name"|"${dotfiles}/tools/claude/custom/skills/$name"|/nix/store/*-home-manager-files/.pi/agent/skills/"$name")
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
