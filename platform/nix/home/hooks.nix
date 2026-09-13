{
  config,
  lib,
  pkgs,
  ...
}:
let
  dotfiles = "${config.home.homeDirectory}/${
    if pkgs.stdenv.hostPlatform.isDarwin then ".dotfiles" else "dotfiles"
  }";
  # Activation runs both during an image build (possibly offline) and on every
  # switch, so every hook is idempotent and offline-tolerant.
  after = lib.hm.dag.entryAfter [ "linkGeneration" ];
  # NOTE: installPackages must be in this list — it installs the profile's
  # packages and runs AFTER ordinary after-hooks. Without it mason ran while
  # ~/.nix-profile still pointed at the previous generation and could not find
  # go in the devops stage, so jsonnet-language-server silently never installed.
  afterNvim = lib.hm.dag.entryAfter [
    "syncNvimPlugins"
    "installPackages"
  ];

  # Where home.packages ACTUALLY end up, which is not one place:
  #   ~/.nix-profile/bin           — standalone home-manager (DevPod, containers)
  #   /etc/profiles/per-user/<u>   — home-manager as a NixOS/nix-darwin module with
  #                                  useUserPackages; ~/.nix-profile stays EMPTY there
  #   /run/current-system/sw/bin   — the system profile: `go` on the mac, and
  #                                  perl/shasum on NixOS, which has no /usr/bin at all
  # NOTE: this list is what the NixOS stand turned up. With only ~/.nix-profile/bin,
  # mason found neither python3 nor go and silently skipped seven packages
  # (basedpyright, debugpy, mypy, yamllint, ansible-lint, jsonnet-language-server).
  # A path that does not exist on a given host costs nothing.
  profilePath = lib.concatStringsSep ":" [
    "${config.home.homeDirectory}/.nix-profile/bin"
    "/etc/profiles/per-user/${config.home.username}/bin"
    "/run/current-system/sw/bin"
  ];

  # NOTE: a file, not a shell variable — DAG entries are not guaranteed to share
  # one shell, and the file survives the activation for reading afterwards.
  w = import ./warn.nix { inherit config; };
  warnFile = w.file;
  warn = w.mk;
in
{
  home.activation = {
    # Reset the accumulator before any hook, or the summary would show last
    # activation's warnings.
    initWarnings = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      run mkdir -p "$(dirname "${warnFile}")"
      run rm -f "${warnFile}"
    '';

    # sshSockets lives in darwin.nix: the ControlMaster config is mac-only.

    # NOTE: Claude Code is deliberately NOT a nix package — the official binary
    # self-updates, which an immutable store cannot do.
    # NOTE: `:/usr/bin:/bin` at the tail because the activation PATH carries no
    # system paths at all, and the installer calls shasum (a perl script in
    # /usr/bin).
    # NOTE: profilePath is here for shasum too — NixOS has no /usr/bin, so perl and
    # shasum are reachable only through /run/current-system/sw/bin, and without it the
    # installer died and the step reported a bogus "offline?".
    installClaudeCode = after ''
      if [ ! -x "$HOME/.local/bin/claude" ] && ! command -v claude >/dev/null 2>&1; then
        run ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh \
          && PATH="${profilePath}:${
            lib.makeBinPath [
              pkgs.curl
              pkgs.coreutils
              pkgs.gnutar
              pkgs.gzip
              pkgs.unzip
            ]
          }:$PATH:/usr/bin:/bin" \
             run ${pkgs.bash}/bin/bash /tmp/claude-install.sh \
          && run rm -f /tmp/claude-install.sh \
          || ${warn "claude install skipped (offline?)"}
      fi
    '';

    # NOTE: ZSHRC=/dev/null — otherwise the installer appends its annex block
    # through the ~/.zshrc symlink straight into the repo, and our .zshrc
    # already has a zinit block.
    installZinit = after ''
      if [ ! -d "$HOME/.local/share/zinit" ]; then
        run ${pkgs.curl}/bin/curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh -o /tmp/zinit-install.sh \
          && PATH="${
            lib.makeBinPath [
              pkgs.git
              pkgs.curl
              pkgs.coreutils
              # NOTE: the activation PATH has neither /usr/bin nor
              # ~/.nix-profile/bin, so without this the installer printed
              # "zsh: command not found" twice and skipped the annexes.
              pkgs.zsh
            ]
          }:$PATH" NO_INPUT=1 ZSHRC=/dev/null \
             run ${pkgs.bash}/bin/bash /tmp/zinit-install.sh \
          && run rm -f /tmp/zinit-install.sh \
          || ${warn "zinit install skipped (offline?)"}
      fi
    '';

    # CRD schemas cached locally so yamlls works offline and without a network
    # lag on first open; yamlls.lua prefers the file:// cache and falls back to
    # the URL.
    cacheYamlSchemas = after ''
      SCHEMA_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/yaml-schemas"
      CRD_BASE="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main"
      for rel in \
        argoproj.io/application_v1alpha1.json \
        gateway.networking.k8s.io/gateway_v1.json \
        gateway.networking.k8s.io/gatewayclass_v1.json \
        gateway.networking.k8s.io/httproute_v1.json \
        gateway.networking.k8s.io/referencegrant_v1beta1.json; do
        if [ ! -f "$SCHEMA_DIR/$rel" ]; then
          run mkdir -p "$SCHEMA_DIR/$(dirname "$rel")"
          run ${pkgs.curl}/bin/curl -fsSL "$CRD_BASE/$rel" -o "$SCHEMA_DIR/$rel" \
            || { m="schema $rel not cached (yamlls falls back to URL)"; \
                 echo "warn: $m"; echo "$m" >> "${warnFile}"; }
        fi
      done
      # GitLab CI gains keywords every release, so unlike the CRDs it is refreshed once
      # it is a month old; the old copy stays if the download fails.
      ci="$SCHEMA_DIR/gitlab-ci.json"
      if [ -z "$(find "$ci" -mtime -30 2>/dev/null)" ]; then
        run mkdir -p "$SCHEMA_DIR"
        run ${pkgs.curl}/bin/curl -fsSL \
          "https://gitlab.com/gitlab-org/gitlab-foss/-/raw/master/app/assets/javascripts/editor/schema/ci.json" \
          -o "$ci.tmp" && run mv "$ci.tmp" "$ci" \
          || { rm -f "$ci.tmp"; m="schema gitlab-ci.json not refreshed (yamlls uses the old copy or the URL)"; \
               echo "warn: $m"; echo "$m" >> "${warnFile}"; }
      fi
    '';

    # NOTE: the init.lua guard is what skips this during an image build before
    # COPY tools/nvim — without the config the ~/.config/nvim symlink dangles.
    # NOTE: no guard on the lazy directory. `Lazy! sync` is install + clean +
    # update, it is idempotent and must run on every activation, or a newly
    # added plugin would never arrive through updl/updm because the directory
    # already exists. Plugins are deliberately unpinned: lazy-lock.json is
    # gitignored, so versions are always fresh — the same contract as zinit
    # update in updl.
    # NOTE: nvim from pkgs — on darwin it lives in the system profile, not
    # ~/.nix-profile.
    syncNvimPlugins = after ''
      if [ -e "$HOME/.config/nvim/init.lua" ]; then (
        PATH="${profilePath}:${
          lib.makeBinPath (
            [
              pkgs.git
              pkgs.neovim
              pkgs.curl
              pkgs.gnutar
              pkgs.gzip
              pkgs.tree-sitter
            ]
            # `cc` for the parser build; see the gcc note in default.nix
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.gcc ]
          )
        }:$PATH:/usr/bin:/bin"
        export PATH

        run nvim --headless "+Lazy! sync" +qa \
          || ${warn "nvim Lazy sync failed (offline?)"}

        # NOTE: parsers need their own step. ts.install() installs only MISSING
        # parsers and silently skips one already present, even when the plugin
        # has moved on and its queries no longer match the grammar — that is how
        # jinja, diff and nix drifted and .j2 highlighting disappeared with no
        # error. `build = ':TSUpdate'` does not help: it fires only when the
        # plugin itself updates. update() compares revisions and takes ~6s with
        # fresh parsers, hence no guard.
        run nvim --headless -c 'lua local h = require("nvim-treesitter").update(); if h then h:wait(600000) end' +qa \
          || ${warn "treesitter update failed (offline?)"}
      ); fi
    '';

    # Mason packages (LSP servers, linters, formatters from ensure_installed).
    # NOTE: a separate step after Lazy sync, with the Sync variant — the async
    # command would let nvim exit before the install finishes. The command
    # itself lazy-loads mason-tool-installer (its own spec in lsp.lua).
    # NOTE: no guard on the mason directory either. The command is idempotent
    # and costs 0s when complete, while "skip if something is installed" would
    # break the multi-stage image: the devops stage inherits a non-empty mason/
    # from core and would not deliver jsonnet-language-server, which needs go
    # (devops profile only).
    # NOTE: /run/current-system/sw/bin is nix-darwin's system profile — on the
    # mac go lives there rather than in ~/.nix-profile, and without it mason
    # logged "Could not find executable go in PATH" and skipped the package. On
    # Linux the path simply does not exist.
    installMasonTools = afterNvim ''
      # NOTE: a subshell — every home.activation entry is concatenated into ONE
      # bash script, so an export here would leak into installZinit and
      # setupDevpod.
      if [ -e "$HOME/.config/nvim/init.lua" ]; then (
        MASON_LOG="$HOME/.local/state/nvim/mason.log"
        # guard: on a virgin machine the log does not exist yet and the redirect
        # would print a noisy error into the activation's stderr
        LOG_POS=$([ -f "$MASON_LOG" ] && wc -c < "$MASON_LOG" || echo 0)
        # NOTE: python is deliberately absent from makeBinPath. This step runs
        # after installPackages and the profile comes first in PATH, so a
        # declared package never wins — it only created the illusion that the
        # version was pinned while venvs were actually built against the system
        # python.
        # NOTE: wget explicitly. Some mason packages fetch their release archive with
        # wget and do NOT fall back to curl; on the NixOS stand that failed with a
        # bare ENOENT, because there is no /usr/bin to borrow one from. It did not
        # make terraform-ls install — that one 404s upstream — but it is what turned
        # an invisible PATH problem into the real error.
        PATH="${profilePath}:${
          lib.makeBinPath (
            [
              pkgs.git
              pkgs.neovim
              pkgs.curl
              pkgs.wget
              pkgs.gnutar
              pkgs.gzip
              pkgs.unzip
              pkgs.nodejs_24
              pkgs.luarocks
              pkgs.uv
            ]
            # luacheck builds luafilesystem, a C module
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.gcc ]
          )
        }:$PATH:/usr/bin:/bin"
        export PATH

        # NOTE: mason venvs break in two independent ways and mason notices neither —
        # the directory is there, so the package counts as installed:
        #   1. the profile's python minor changed (3.13 → 3.14), so site-packages sits in
        #      the old lib/pythonX.Y and the import fails — mypy, yamllint and
        #      ansible-lint went that way silently;
        #   2. the venv was built against a store-path python that nix-collect-garbage
        #      (the tail of updm) then removed — there the interpreter itself is gone.
        # The first is invisible by running it, the second invisible by version, so both
        # are checked.
        MASON_BIN="$HOME/.local/share/nvim/mason/bin"
        rebuilt=""
        if command -v python3 >/dev/null; then
          PYVER=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
          for cfg in "$HOME"/.local/share/nvim/mason/packages/*/venv/pyvenv.cfg; do
            [ -e "$cfg" ] || continue
            pkgdir=''${cfg%/venv/pyvenv.cfg}
            venv_ver=$(sed -n 's/^version *= *//p' "$cfg" | cut -d. -f1,2)
            reason=""
            if [ "$venv_ver" != "$PYVER" ]; then
              reason="собран на python $venv_ver, сейчас $PYVER"
            elif ! "$pkgdir/venv/bin/python" -c "" >/dev/null 2>&1; then
              reason="интерпретатор venv не запускается"
            fi
            if [ -n "$reason" ]; then
              echo "mason: $(basename "$pkgdir") — $reason, пересобираем"
              # NOTE: through `run`, not directly — under `switch -n` it prints
              # the command instead of executing it. Without it a dry run really
              # deleted package directories.
              run rm -rf "$pkgdir"
              rebuilt=1
            fi
          done
          # NOTE: deleting the package directory is not enough — symlinks to its
          # binaries remain in mason/bin and the reinstall fails with EEXIST.
          # Caught on a live switch: ruff and debugpy were removed and could not
          # come back, and ruff vanished from the system entirely. Cleaned by
          # being broken, not by package name: the binary name need not match
          # (debugpy → debugpy-adapter).
          if [ -n "''${rebuilt:-}" ] && [ -d "$MASON_BIN" ]; then
            find "$MASON_BIN" -type l ! -exec test -e {} \; -print -delete
          fi
        fi

        run nvim --headless "+MasonToolsInstallSync" +qa \
          || ${warn "mason tools install failed (offline?)"}
        if [ -f "$MASON_LOG" ]; then
          # NOTE: the log check is mandatory — MasonToolsInstallSync returns 0
          # even when a package fails, so a failure shows up in neither the exit
          # code nor the summary. Only the tail this run appended is examined.
          # NOTE: `|| true` is mandatory too — activate runs under `set -eu -o
          # pipefail` and a grep with no match returns 1, so a SUCCESSFUL mason
          # run aborted the activation before installZinit, setupDevpod and the
          # summary itself.
          FAILED=$(tail -c "+$((LOG_POS + 1))" "$MASON_LOG" \
            | grep -o 'Installation failed for Package(name=[^)]*)' \
            | sed 's/.*name=//; s/)$//' | sort -u | tr '\n' ' ' || true)
          if [ -n "$FAILED" ]; then
            m="mason: не установлено — $FAILED(подробности: $MASON_LOG)"
            echo "warn: $m"; echo "$m" >> "${warnFile}"
          fi
        fi
      ); fi
    '';

    # Private submodule (over ssh) plus the MCP servers; a soft skip without
    # keys.
    # NOTE: PATH must carry claude (~/.local/bin), uv and npm explicitly — the
    # activation PATH has none of them, and context7 was silently skipped
    # without this.
    installClaudeCustom = after ''
      if [ -d "${dotfiles}/.git" ]; then
        if [ ! -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          # NOTE: /usr/bin first on purpose — git only looks up `ssh` in PATH,
          # and the system build understands GSSAPIAuthentication from
          # /etc/ssh/ssh_config while nix-openssh is built without GSSAPI and
          # prints "Unsupported option". nix-openssh stays as the fallback for
          # images with no system ssh.
          PATH="/usr/bin:/bin:${lib.makeBinPath [ pkgs.openssh ]}:$PATH" \
            run ${pkgs.git}/bin/git -C "${dotfiles}" submodule update --init tools/claude/custom \
            || ${warn "claude custom submodule skipped (нет ssh-агента или ключа)"}
        fi
        if [ -f "${dotfiles}/tools/claude/custom/install.sh" ]; then
          PATH="$HOME/.local/bin:${
            lib.makeBinPath [
              pkgs.git
              pkgs.uv
              pkgs.nodejs_24
            ]
          }:$PATH:/usr/bin:/bin" \
            run "${dotfiles}/tools/claude/custom/install.sh" \
            || ${warn "MCP install failed"}
        fi
      fi
    '';

    # The summary runs last. Activation still succeeds — offline must not break
    # it — but skipped steps are now visible immediately instead of a week later
    # in nvim.
    reportWarnings =
      lib.hm.dag.entryAfter
        [
          "installClaudeCode"
          "installZinit"
          "cacheYamlSchemas"
          "syncNvimPlugins"
          "installMasonTools"
          "installClaudeCustom"
        ]
        ''
          if [ -s "${warnFile}" ]; then
            echo ""
            echo "  ВНИМАНИЕ: активация прошла, но $(wc -l < "${warnFile}" | tr -d ' ') шаг(ов) пропущено:"
            sed 's/^/    - /' "${warnFile}"
            echo "  подробности: ${warnFile}"
            echo ""
          fi
        '';
  };
}
