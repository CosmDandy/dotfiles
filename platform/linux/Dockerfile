# Prebuilt devcontainer image for DevPod: Ubuntu + Nix + home-manager. Built in
# CI for amd64+arm64 as ghcr.io/cosmdandy/devcontainer:{core,devops}. Store
# paths match the repo's flake.lock, so home-manager switch on `devpod up` is an
# instant no-op.
#
# The profile is a stage, not a build-arg: devops inherits core, so the lower
# layers are literally the same and the registry deduplicates them — with :core
# in hand a client pulls :devops as one delta.
#
# NOTE: nix-collect-garbage MUST stay in the SAME RUN as the switch. Deleting in
# a separate layer frees nothing — the files stay in the lower layer under a
# whiteout (measured: 68 MiB against 8 MiB), and build dependencies like
# terraform's Go toolchain would be baked in forever.

# ubuntu-24.04, pinned by the multi-arch index digest
FROM mcr.microsoft.com/devcontainers/base@sha256:d94c97dd9cacf183d0a6fd12a8e87b526e9e928307674ae9c94139139c0c6eae AS base

ENV TZ=Europe/Moscow \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# The user comes from Microsoft's base image as vscode with uid 1000.
# NOTE: RENAMED, not recreated — devpod's bind-mount permissions depend on uid
# 1000 and a new user would get 1001. It must happen first in the stage, while
# nobody is logged in as them (usermod -m moves the home directory) and before
# any USER.
# NOTE: the uid must stay 1000. Where it differs from the docker host's user,
# devpod "fixes" it with a recursive chown of $HOME — 1.5 GB / 54847 files over
# overlay2 with metacopy=false, measured at 8.5 minutes and a broken /nix.
# Disabled through updateRemoteUserUID in .devcontainer/devcontainer.json.
# NOTE: the sudo rule lives in /etc/sudoers.d/vscode and usermod does NOT follow
# it, so without the rename cosmdandy would simply have no sudo — which
# .devcontainer/setup.sh relies on when running on a bare image.
RUN usermod -l cosmdandy -d /home/cosmdandy -m vscode \
  && groupmod -n cosmdandy vscode \
  && sed -i 's/^vscode /cosmdandy /' /etc/sudoers.d/vscode \
  && mv /etc/sudoers.d/vscode /etc/sudoers.d/cosmdandy \
  && apt-get update \
  && apt-get install -y --no-install-recommends zsh python3-pip python3-venv locales \
  && rm -rf /var/lib/apt/lists/* \
  && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
  && locale-gen \
  && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  && ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime \
  && echo "$TZ" > /etc/timezone \
  && chsh -s /usr/bin/zsh cosmdandy \
  # NOTE: the same PATH as ENV below, duplicated on purpose. devpod runs
  # lifecycle hooks through su, which resets the environment to the system
  # default and drops the image's ENV along with ~/.nix-profile/bin. Nothing
  # restores it at that point: ~/.zprofile points into ~/dotfiles, which is
  # removed below and reappears only after the hooks. /etc/zsh/zshenv is read by
  # every zsh, including `zsh -c`, and ignores dangling symlinks in $HOME.
  # Without it `postCreateCommand: npm ci` exits 127 with npm present.
  && printf '%s\n' \
       'if [[ -d "$HOME/.nix-profile/bin" && ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]]; then' \
       '  export PATH="$HOME/.nix-profile/bin:$PATH"' \
       'fi' >> /etc/zsh/zshenv \
  && mkdir -m 0755 /nix && chown cosmdandy:cosmdandy /nix \
  # marker for .devcontainer/setup.sh: system prep is already in the image
  && echo prebuilt > /etc/devcontainer-prebuilt

USER cosmdandy
ENV USER=cosmdandy \
    HOME=/home/cosmdandy
WORKDIR /home/cosmdandy

# NOTE: devcontainers reads remoteUser from the devcontainer.metadata LABEL, not
# from the USER directive above. Work repositories get this image via
# --devcontainer-image and set no remoteUser of their own, so the label is their
# only source of truth — without it their `devpod up` asks for a vscode that no
# longer exists.
# NOTE: the value is overwritten whole (LABEL cannot append), dropping the
# common-utils and git feature ids. Harmless — no devcontainer.json here
# requests features. onCreateCommand lives here for the same reason: work
# repositories have no devcontainer.json, and the label is the only place
# provisioning can reach them from.
LABEL devcontainer.metadata='[{"remoteUser":"cosmdandy","onCreateCommand":"/usr/local/bin/dotfiles-provision"}]'

# Nix single-user, version pinned and checksum-verified. This is the `single`
# mode of platform/linux/install.sh, fixed rather than probed: an image build has
# no systemd for a daemon to be supervised by, and neither does the container it
# becomes.
# NOTE: --no-channel-add — everything comes from the flake, and a channel would
# bake ~400MB of unpinned nixpkgs-unstable into the image past
# nix-collect-garbage.
RUN curl -fsSL https://releases.nixos.org/nix/nix-2.33.1/install -o /tmp/nix-install \
  && echo "2bbe0d388d1bee5ee60ed67b844f428b6031a1b7c42d7d03319ad7133867290d  /tmp/nix-install" | sha256sum -c - \
  && sh /tmp/nix-install --no-daemon --no-channel-add \
  && rm /tmp/nix-install \
  && mkdir -p "$HOME/.config/nix" \
  && echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"

ENV PATH=/home/cosmdandy/.nix-profile/bin:$PATH

COPY --chown=cosmdandy:cosmdandy platform/nix /opt/dotfiles/platform/nix

# NOTE: the nvim config has to exist for the activation hooks — home-manager
# links ~/.config/nvim into ~/dotfiles, and with a dangling symlink the `-e
# init.lua` guard fails, syncNvimPlugins/installMasonTools are skipped silently,
# and 1.2 GB of plugins and mason downloads into EVERY workspace.
# NOTE: it lives in /opt, not ~/dotfiles — devpod clones the real repository
# there and a non-empty directory would break the clone. Each stage symlinks
# ~/dotfiles -> /opt for the activation and removes it in the same RUN.
# NOTE: the symlink must be recreated in EVERY stage. While core removed the
# directory outright, devops was left with a dangling one and skipped mason
# entirely — which is why jsonnet-language-server (needs go, only in devops)
# could never reach the image.
COPY --chown=cosmdandy:cosmdandy tools/nvim /opt/dotfiles/tools/nvim

# .zshrc for the same reason: zinit clones five plugins (~13 MB) on the first
# interactive shell, which the user saw as a pause with progress bars in every
# workspace. One `zsh -i -c exit` at build time is enough — the `wait lucid`
# scheduler finishes first.
COPY --chown=cosmdandy:cosmdandy tools/zsh /opt/dotfiles/tools/zsh

# NOTE: github's host keys must be in the system known_hosts. Provisioning runs
# from a lifecycle hook, which has no tty, so the default `StrictHostKeyChecking
# ask` cannot ask and git over ssh dies with "Host key verification failed" —
# the forwarded agent is there, only the host key was missing. Fetched at build
# time rather than hardcoded, so a key rotation is fixed by the weekly rebuild.
USER root
RUN ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> /etc/ssh/ssh_known_hosts \
  && chmod 644 /etc/ssh/ssh_known_hosts
USER cosmdandy

# NOTE: a thin wrapper that LIVES IN THE IMAGE, not a direct call to install.sh
# — the wrapper is what updates the clone install.sh lives in, and rewriting a
# running script under itself breaks wherever the shell happens to be reading.
# The exec comes after the update. It uses reset --hard rather than pull: the
# baked clone is a week behind main and holds no work of its own. Offline is not
# fatal — it runs on the baked copy.
COPY --chown=root:root platform/linux/dotfiles-provision /usr/local/bin/dotfiles-provision

# Generation marker: hash of the source tree the baked home-manager generation
# is built from. platform/linux/install.sh hashes the fresh clone and, on a
# match, skips the switch and every activation hook — that is what makes devpod
# up take seconds.
# NOTE: MUST stay byte-identical with generation_hash() there. The darwin
# exclusions mirror the CI rebuild triggers, and lazy-lock.json is out because
# it is gitignored and therefore absent from any clone.
# NOTE: stamped HERE, in the pristine tree straight after the COPY. `Lazy! sync`
# writes lazy-lock.json into tools/nvim during the core stage, so a hash taken
# afterwards described a tree no clone can reproduce and the skip silently never
# fired.
RUN (cd /opt/dotfiles && find platform/nix tools/nvim -type f \
       ! -path platform/nix/darwin-configuration.nix \
       ! -path platform/nix/home/darwin.nix \
       ! -name lazy-lock.json -print0 \
     | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1) \
    > "$HOME/.dotfiles-generation"

# --- core: editor, shell, git, CI ---
FROM base AS core
# NOTE: the submodule commit the MCP set below is baked against. CI writes it
# and install.sh compares it with the pointer in the clone; a mismatch means the
# set changed after the build and the submodule installer must run. Without this
# check a new server (or a corrected address, as happened with timing) would not
# reach containers until the next image rebuild, silently. `unknown` makes a
# hand-built image fail the comparison, i.e. err towards running the installer.
ARG CUSTOM_SHA=unknown
RUN ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#cosmdandy-core-$(uname -m)-linux" -b hm-backup \
  # zinit plugins: core only, devops inherits them with the layer. `|| true`
  # because the shell may exit non-zero over trivia like a missing TERM, long
  # after the clone.
  # NOTE: ZSH_NO_DEFER is what makes this work at all now. .zshrc defers zinit
  # (and atuin, and direnv) onto a `zle -F` handler that fires when the line
  # editor first goes idle — which never happens in `zsh -i -c exit`, so the
  # queue was carried out of the build unrun and every container cloned the
  # plugins again on its first prompt. Measured: 5 commands left in the queue
  # without it, 0 with it.
  && (ZSH_NO_DEFER=1 zsh -i -c exit >/dev/null 2>&1 || true) \
  # MCP servers baked whole: the binaries AND their registration in
  # ~/.claude.json, which lives in $HOME and therefore ships with the image.
  # install.sh checks exactly this end state and skips the submodule's installer
  # — worth 6 s of every devpod up. The submodule itself cannot be baked
  # (private repo, public image); its ~/.claude/* symlinks can, and dangle until
  # the workspace clones it, which is legal.
  # NOTE: absolute paths — ENV PATH here has no ~/.local/bin, zshrc adds that.
  # NOTE: the timing url must match the one in tools/claude/custom/install.sh.
  && uv tool install mcp-atlassian \
  && npm install -g --prefix "$HOME/.npm-global" @upstash/context7-mcp \
  && "$HOME/.local/bin/claude" mcp add -s user atlassian -- "$HOME/.local/bin/mcp-atlassian" \
  && "$HOME/.local/bin/claude" mcp add -s user context7 -- "$HOME/.npm-global/bin/context7-mcp" \
  && "$HOME/.local/bin/claude" mcp add -s user -t http timing "http://100.64.0.1:7233/mcp" \
  # NOTE: rm before ln, and assert afterwards. `ln -sfn` onto a destination that
  # is a REAL directory neither replaces it nor fails — -n only guards a symlink
  # to a directory, so ln follows the real one and quietly creates the link
  # INSIDE it, exit 0. Only `skills` is checked at runtime, so the rest would be
  # silently absent from every workspace with both the build and install.sh
  # green.
  && for d in skills agents commands rules labs output-styles; do \
       rm -rf "$HOME/.claude/$d" \
       && ln -s "$HOME/dotfiles/tools/claude/custom/$d" "$HOME/.claude/$d" \
       && [ -L "$HOME/.claude/$d" ] || exit 1; \
     done \
  && echo "$CUSTOM_SHA" > "$HOME/.claude/.mcp-baked-from" \
  && rm -f "$HOME/dotfiles" \
  # The dotfiles clone is baked in; dotfiles-provision only catches it up to
  # origin.
  # NOTE: must come AFTER `rm -f $HOME/dotfiles` — before that it is a symlink
  # to /opt/dotfiles and clone into an existing path fails. Cloned over https
  # (the build has no agent and no keys), with origin switched to ssh so the
  # user can push memory back from inside the container.
  && git clone --quiet --depth 1 https://github.com/CosmDandy/dotfiles.git "$HOME/dotfiles" \
  && git -C "$HOME/dotfiles" remote set-url origin git@github.com:CosmDandy/dotfiles.git \
  # NOTE: mason build caches (npm ~71 MB, go ~66 MB, pip ~121 MB) must be
  # cleaned in the SAME RUN or they stay under a whiteout. pip caches the venv
  # wheels and is the largest.
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
            "$HOME/.cache/pip" "$HOME/.cache/uv" \
  && nix-collect-garbage -d \
  && echo core > "$HOME/.dotfiles-profile"

# --- devops: core + IaC/K8s/container ---
FROM core AS devops
# NOTE: rm -rf, not just ln — core leaves a REAL clone in ~/dotfiles, and `ln
# -sfn` onto an existing directory silently links inside it (same trap as
# ~/.claude/* above). This stage puts its own clone back at the end.
RUN rm -rf "$HOME/dotfiles" \
  && ln -sfn /opt/dotfiles "$HOME/dotfiles" \
  && nix run --inputs-from /opt/dotfiles/platform/nix home-manager -- \
      switch --flake "/opt/dotfiles/platform/nix#cosmdandy-devops-$(uname -m)-linux" -b hm-backup \
  # NOTE: the warm-up repeats here for a different reason than in core —
  # completions are generated by .zshrc on first shell start, and devops brings
  # kubectl, helm, talosctl and k9s, which core did not have. It MUST come after
  # the switch: before it those binaries do not exist yet.
  && (zsh -i -c exit >/dev/null 2>&1 || true) \
  && rm -f "$HOME/dotfiles" \
  && rm -rf "$HOME/.npm" "$HOME/.cache/go-build" "$HOME/go/pkg/mod/cache" \
            "$HOME/.cache/pip" \
  && nix-collect-garbage -d \
  && echo devops > "$HOME/.dotfiles-profile" \
  && git clone --quiet --depth 1 https://github.com/CosmDandy/dotfiles.git "$HOME/dotfiles" \
  && git -C "$HOME/dotfiles" remote set-url origin git@github.com:CosmDandy/dotfiles.git
