#!/usr/bin/env zsh

set -e
START_TIME=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLATFORM_DIR/common.sh"

# Thin bootstrap: packages, symlinks and installers are declared in
# platform/nix/home/ and applied by a single home-manager switch. Only the
# irreducible minimum lives here.
#
# Profiles: core | devops
# Usage: PROFILE=core ./install.sh
#    or: devpod up --dotfiles-script-env PROFILE=core
#
# NOTE: without an explicit variable the profile comes from the marker the
# prebuilt image writes. Otherwise a :core image would get the devops profile
# rolled onto it, pulling terraform, ansible, kubectl and k9s into the
# container's personal layer — measured at 5m41s against ~20s.
PROFILE="${PROFILE:-$(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo devops)}"
print_section "Profile: ${PROFILE}"

# Nix install mode. Two shapes, and the difference is not cosmetic:
#   single — /nix belongs to the user, no daemon, builds run as the user. The
#            only shape a container can have: no init to supervise a daemon, no
#            root at runtime, and one user with nobody to share the store with.
#   multi  — /nix belongs to root and nix-daemon builds in a sandbox under its
#            own nixbld users, so store signatures mean something and a build
#            cannot reach the invoking user's files. Wanted on anything
#            long-lived that holds real keys: servers, VMs, OrbStack machines.
# NOTE: the probe is systemd, not "am I in a container" — an OrbStack machine
# looks like a container by every marker (/opt/orbstack-guest, no hardware) and
# is nevertheless a full systemd system that should get the daemon. What the
# daemon needs is an init to be supervised by, so that is what gets asked.
# NOTE: left to itself the upstream installer picks single-user under a pipe,
# having no tty to ask on — which is how every machine here quietly ended up
# single-user regardless of what it was.
NIX_INSTALL="${NIX_INSTALL:-auto}"
if [[ "$NIX_INSTALL" == "auto" ]]; then
  if [[ -d /run/systemd/system ]]; then
    NIX_INSTALL=multi
  else
    NIX_INSTALL=single
  fi
fi

# NOTE: nix.sh exports nothing at all unless BOTH $HOME and $USER are set — it
# guards on them. A `docker exec`, a cron job or a systemd unit started without
# the environment supplies neither, so sourcing the profile quietly does nothing
# and the next command dies with "command not found: nix", pointing nowhere near
# the cause. Caught in a bare container while testing the single-user path.
export USER="${USER:-$(id -un)}"

# Adopt an existing installation before deciding to create one.
# NOTE: a non-interactive shell reads neither /etc/profile nor ~/.profile, so on
# a machine where nix is installed `command -v nix` answers "absent" and the
# block below runs the installer a second time. With a daemon that is not a
# harmless no-op: the installer finds its own leftovers (/etc/bash.bashrc.backup
# -before-nix and friends), refuses, and takes the whole run down with it —
# after the daemon, the store and the nixbld users are all already in place.
for nix_profile in \
  /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
  "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
  [[ -e "$nix_profile" ]] && . "$nix_profile"
done

# NOTE: --no-channel-add — packages come from flake.lock, and the default
# channel would pull ~400MB of unpinned tree.
if ! command -v nix &> /dev/null; then
  print_section "Installing Nix (${NIX_INSTALL}-user)"
  NIX_INSTALLER=/tmp/nix-install.sh
  curl -fsSL https://nixos.org/nix/install -o "$NIX_INSTALLER"
  if [[ "$NIX_INSTALL" == "multi" ]]; then
    # --yes: the daemon installer is interactive by default and there is no tty.
    sh "$NIX_INSTALLER" --daemon --yes --no-channel-add
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  else
    sh "$NIX_INSTALLER" --no-daemon --no-channel-add
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi
  rm -f "$NIX_INSTALLER"
fi

# Flakes are needed by home-manager; vanilla nix does not enable them.
mkdir -p "$HOME/.config/nix"
if ! grep -q "experimental-features" "$HOME/.config/nix/nix.conf" 2>/dev/null; then
  echo "experimental-features = nix-command flakes" >> "$HOME/.config/nix/nix.conf"
fi

# With a daemon the CLIENT config above is only half of it: the daemon carries
# its own settings and its own idea of who is allowed to override them.
# NOTE: trusted-users is what lets this user pass substituters and similar
# settings through to a build at all. Without it the daemon ignores them in
# silence, and the only symptom is a rebuild where a cache hit was expected.
if [[ -S /nix/var/nix/daemon-socket/socket ]]; then
  NIX_CONF=/etc/nix/nix.conf
  nix_conf_changed=""
  grep -q "experimental-features" "$NIX_CONF" 2>/dev/null \
    || { echo "experimental-features = nix-command flakes" | sudo tee -a "$NIX_CONF" >/dev/null; nix_conf_changed=1; }
  grep -q "^trusted-users" "$NIX_CONF" 2>/dev/null \
    || { echo "trusted-users = root $(whoami)" | sudo tee -a "$NIX_CONF" >/dev/null; nix_conf_changed=1; }
  [[ -n "$nix_conf_changed" ]] && sudo systemctl restart nix-daemon
fi

# Bridge symlinks: the home modules reference ~/dotfiles, the configs
# historically ~/.dotfiles, and DevPod's clone path is not configurable.
[[ "$DOTFILES_ROOT" != "$HOME/.dotfiles" && ! -e "$HOME/.dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/.dotfiles"
[[ "$DOTFILES_ROOT" != "$HOME/dotfiles" && ! -e "$HOME/dotfiles" ]] && ln -sf "$DOTFILES_ROOT" "$HOME/dotfiles"

# NOTE: shallow first, full clone on failure. `--depth 1` fetches only the
# branch tip, so the moment a submodule gains a commit while the superproject
# still pins the previous one — the normal state between pointer bumps — the
# pinned commit is missing and the checkout fails.
submodule_init() {
  git -C "$DOTFILES_ROOT" submodule update --init --depth 1 "$1" 2>/dev/null \
    || git -C "$DOTFILES_ROOT" submodule update --init "$1"
}

# The private submodule must come BEFORE the switch — symlinks from the home
# modules point inside it.
# NOTE: a HARD failure, not a warn. A missing submodule does not break the
# install visibly, it breaks it silently: the symlink is there, the file is not,
# git skips the missing include, and work repositories get the personal identity
# with the wrong signing key — noticed only from invalid commits in history,
# when fixing is expensive.
# NOTE: the actual file is checked, not just the exit code — `submodule update`
# returns 0 for a registered-but-not-checked-out submodule.
print_section "Initializing private submodule"
if ! submodule_init private \
   || [[ ! -f "$DOTFILES_ROOT/private/git/includes.conf" ]]; then
  echo "✖ FATAL: сабмодуль private не подтянулся." >&2
  echo "  Без него git подставит личную идентичность в рабочих репозиториях" >&2
  echo "  и подпишет коммиты не тем ключом — молча." >&2
  echo "  Причина обычно одна: в контейнер не проброшен ssh-агент с ключом к" >&2
  echo "  github.com (см. IdentityAgent в блоке Host *.devpod на хосте)." >&2
  exit 1
fi

# The whole user space in one switch: packages, symlinks and activation hooks,
# pinned by flake.lock. Attribute: <user>-<profile>-<arch>, see
# platform/nix/flake.nix
FLAKE_DIR="$DOTFILES_ROOT/platform/nix"
HM_CONFIG="$(whoami)-${PROFILE}-$(uname -m)-linux"

# Generation marker: the prebuilt image stamps ~/.dotfiles-generation with a
# hash of everything its baked generation was built from. When the clone hashes
# to the same value the baked generation is already what a switch would produce
# — out-of-store symlinks resolve through ~/dotfiles and start pointing into the
# fresh clone by themselves — so the switch and every activation hook are
# skipped. Freshness is not this script's job: updl and the nightly
# devpod-update.sh still switch unconditionally.
#
# NOTE: the hash must be computed identically here and in
# platform/linux/Dockerfile.
# NOTE: darwin-only files are excluded to mirror the CI rebuild triggers — they
# never affect the Linux generation, but a mac-only commit would otherwise flip
# the hash with no rebuilt image and force a pointless full switch until the
# next weekly build.
# NOTE: LC_ALL=C on both sides — `sort` collates by locale, and this very file
# set orders differently between C and en_US.UTF-8 (tools/nvim/.stylua.toml
# moves from position 10 to 47). An ssh client sending LC_* is enough to break
# it, and the only symptom would be the skip quietly never firing.
# NOTE: lazy-lock.json is excluded because it is not part of the source tree —
# gitignored, absent from a fresh clone, and written by `Lazy! sync`. Left in,
# the two sides hashed different trees and the skip never fired.
generation_hash() {
  (cd "$DOTFILES_ROOT" \
    && find platform/nix tools/nvim -type f \
         ! -path platform/nix/darwin-configuration.nix \
         ! -path platform/nix/home/darwin.nix \
         ! -name lazy-lock.json -print0 \
       | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
}
GEN_FILE="$HOME/.dotfiles-generation"
CURRENT_GEN="$(generation_hash)"
# NOTE: the marker only vouches for the profile the image itself baked — rolling
# PROFILE=devops onto a :core image must still go through a full switch.
BAKED_PROFILE="$(cat "$HOME/.dotfiles-profile" 2>/dev/null || echo none)"

if [[ -f "$GEN_FILE" && "$CURRENT_GEN" == "$(cat "$GEN_FILE")" && "$PROFILE" == "$BAKED_PROFILE" ]]; then
  print_section "Prebuilt generation matches — skipping home-manager switch"
  # The one thing the skipped hooks still owe us: the custom submodule, which
  # cannot live in a public image. Shallow — only its working tree is ever read.
  # Soft-fail like the hook it replaces: a missing ssh key must not break the
  # whole setup.
  # NOTE: SYNCHRONOUS on purpose. Backgrounding the clone saves ~3s and the
  # content is only needed once claude starts — but the clone goes over ssh and
  # the forwarded agent belongs to the provisioning session. With one
  # agent-forwarding arrangement the directory came out created and EMPTY: no
  # error, no warn, just Claude's skills, rules and knowledge missing.
  # Intermittent silent loss is worse than a steady cost.
  BAKED_CUSTOM="$(cat "$HOME/.claude/.mcp-baked-from" 2>/dev/null || echo none)"
  PINNED_CUSTOM="$(git -C "$DOTFILES_ROOT" ls-tree HEAD tools/claude/custom | awk '{print $3}')"

  if [[ ! -f "$DOTFILES_ROOT/tools/claude/custom/install.sh" ]]; then
    submodule_init tools/claude/custom \
      || echo "warn: claude custom submodule skipped (нет ssh-агента или ключа)"
  fi
  # The installer is only needed when the image did not already bake its result
  # — both the ~/.claude/* symlinks and the MCP registrations live in $HOME,
  # which ships with the image. Running it anyway cost 6s of the 12s this branch
  # used to take.
  # NOTE: compared against the pinned commit rather than probing for one server
  # name. What the image baked is valid only for the submodule commit it was
  # built against, and that commit is in neither the generation hash nor the CI
  # rebuild triggers — so a changed MCP roster would never reach a new container
  # while a name-probe matched. The comparison also self-heals: a stale image
  # simply fails it and the installer runs.
  if [[ -f "$DOTFILES_ROOT/tools/claude/custom/install.sh" ]] \
     && [[ "$BAKED_CUSTOM" != "$PINNED_CUSTOM" || ! -L "$HOME/.claude/skills" ]]; then
    PATH="$HOME/.local/bin:$PATH" "$DOTFILES_ROOT/tools/claude/custom/install.sh" \
      || echo "warn: MCP install failed"
  fi
else
  print_section "Activating home-manager configuration: ${HM_CONFIG}"
  # NOTE: prefer the home-manager CLI from the profile. It is a thin wrapper
  # that builds "<flake>#…activationPackage", so modules and packages come from
  # flake.lock either way — while `nix run` rebuilds the home-manager package
  # with its full closure (nix, nixos-option, man-db), which nix-collect-garbage
  # swept during the image build and which therefore downloaded again on EVERY
  # devpod up: 106 paths, 66.8 MiB, ~50s. A bare image without the profile falls
  # into the else, where `nix run` is the only way. --inputs-from resolves
  # home-manager through the repo's flake.lock, not a fresh master; -b sends
  # files HM would refuse to overwrite to *.hm-backup.
  if command -v home-manager &> /dev/null; then
    home-manager switch --flake "$FLAKE_DIR#${HM_CONFIG}" -b hm-backup
  else
    nix run --inputs-from "$FLAKE_DIR" home-manager -- switch --flake "$FLAKE_DIR#${HM_CONFIG}" -b hm-backup
  fi
  echo "$CURRENT_GEN" > "$GEN_FILE"
fi

# Profile marker, read by automation/cron/devpod-update.sh
echo "$PROFILE" > "$HOME/.dotfiles-profile"

# System level (sudo): outside home-manager's reach. Already done in the
# prebuilt image — these steps are idempotent and return instantly.
print_section "Setting default shell to zsh"
# NOTE: the SYSTEM zsh wins for the login shell, even once the profile has one
# of its own. /etc/passwd would otherwise point inside ~/.nix-profile, and a
# profile that is broken or simply not there yet leaves no way to log in.
if [[ -x /usr/bin/zsh ]]; then
  ZSH_PATH=/usr/bin/zsh
else
  ZSH_PATH="$(command -v zsh)"
fi
# NOTE: compare against the ACTUAL shell from passwd, not $SHELL — in a session
# already running zsh, $SHELL says zsh while passwd still says bash, and the
# block was skipped.
CURRENT_SHELL="$(getent passwd "$(whoami)" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
  # NOTE: -qx, not -q — without an exact line match the entry was duplicated on
  # every run.
  grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null \
    || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  # NOTE: straight to sudo — plain chsh asks PAM for a password the container
  # user does not have ("chsh: PAM: Authentication failure"). The failure used
  # to be swallowed by `2>/dev/null || true`, so the shell silently stayed bash
  # after every recreate.
  sudo chsh -s "$ZSH_PATH" "$(whoami)" \
    || echo "warn: не удалось сменить шелл на zsh — останется $CURRENT_SHELL"
fi

# Containers default to UTC; override with CONTAINER_TZ at create time.
CONTAINER_TZ="${CONTAINER_TZ:-Europe/Moscow}"
if [[ -f "/usr/share/zoneinfo/$CONTAINER_TZ" ]]; then
  print_section "Setting timezone to ${CONTAINER_TZ}"
  sudo ln -sf "/usr/share/zoneinfo/$CONTAINER_TZ" /etc/localtime
  echo "$CONTAINER_TZ" | sudo tee /etc/timezone >/dev/null
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

print_section "Setup complete. Script execution time: ${MINUTES}m ${SECS}s"
