#!/usr/bin/env bash
# A dedicated ssh-agent for DevPod containers.
#
# DevPod generates the *.devpod blocks in ~/.ssh/config with ForwardAgent yes, and removing
# that line is pointless — it comes back on the next `devpod up`. Forwarding hands the
# container not a key but the right to sign with everything in the agent: any process
# inside can request a signature and log in anywhere with it.
# NOTE: IdentitiesOnly does not help here — it governs which identity is offered during
# authentication, not what the agent contains.
#
# So a second agent runs on its own socket holding only the keys actually used from
# containers. `IdentityAgent` in the `Host *.devpod` block points ssh at that socket, and
# ForwardAgent forwards exactly the selected IdentityAgent.
#
# The socket lives outside ~/.ssh on purpose: it is runtime state, not a config or a key.
#
# NOTE: ssh-agent and ssh-add are called by absolute path — --apple-use-keychain exists
# only in Apple's build from /usr/bin, and nix's openssh shadows it in PATH.

set -uo pipefail

SOCK_DIR="$HOME/.local/state/ssh-agents"
SOCK="$SOCK_DIR/devpod.sock"
KEYS=(id_ed25519_kvt id_ed25519_forge id_ed25519_sign id_ed25519_personal)

mkdir -p "$SOCK_DIR"
chmod 700 "$SOCK_DIR"
# ssh-agent will not start over an existing socket file
rm -f "$SOCK"

/usr/bin/ssh-agent -D -a "$SOCK" &
agent_pid=$!

# NOTE: the socket does not appear instantly — without the wait, ssh-add runs into nothing.
for _ in $(seq 1 50); do
  [[ -S "$SOCK" ]] && break
  sleep 0.1
done
if [[ ! -S "$SOCK" ]]; then
  echo "сокет $SOCK так и не появился" >&2
  exit 1
fi

export SSH_AUTH_SOCK="$SOCK"
for k in "${KEYS[@]}"; do
  key="$HOME/.ssh/$k"
  if [[ ! -f "$key" ]]; then
    echo "нет ключа $key — пропускаю" >&2
    continue
  fi
  # The passphrase comes from the Keychain: this runs as a launchd user agent, i.e. after
  # login, when the Keychain is unlocked.
  /usr/bin/ssh-add --apple-use-keychain "$key" || echo "не добавлен: $key" >&2
done

echo "агент готов, сокет $SOCK:"
/usr/bin/ssh-add -l

# NOTE: launchd keeps the service alive by this process — the agent runs with -D
# (foreground), so wait does not return while it is up.
wait "$agent_pid"
