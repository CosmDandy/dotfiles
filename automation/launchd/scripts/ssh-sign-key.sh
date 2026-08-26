#!/usr/bin/env bash
# Loads the commit-signing key into the system ssh-agent at login.
#
# NOTE: git signs with `user.signingkey = key::ssh-ed25519 …`, and the `key::` form makes
# ssh-keygen look for the private half IN THE AGENT — in that mode it does not read files
# at all. The system agent is only ever filled as a side effect of `AddKeysToAgent yes`
# during ssh connections, and this key is used for no ssh connection, so it never gets
# there by itself. After every reboot the agent comes up without it and `git commit` fails
# with "No private key found for public key".
#
# The dedicated container agent holds this key too, but git talks to whatever socket
# $SSH_AUTH_SOCK points at — the system agent — so it is needed in both.
#
# NOTE: ssh-add by absolute path — --apple-use-keychain exists only in Apple's build from
# /usr/bin, and nix's openssh shadows it in PATH.

set -uo pipefail

KEY="$HOME/.ssh/id_ed25519_sign"

# NOTE: launchd hands a user agent the system ssh-agent socket in the inherited
# environment. Without it there is nowhere to add the key, and that is a broken
# configuration rather than "nothing to do".
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
  echo "SSH_AUTH_SOCK не задан — системный агент недоступен" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "нет ключа $KEY" >&2
  exit 1
fi

# Idempotent by fingerprint rather than by invocation: a repeat ssh-add would silently
# rewrite the agent entry and hit the Keychain for nothing.
fp=$(/usr/bin/ssh-keygen -lf "$KEY.pub" 2>/dev/null | awk '{print $2}')
if [[ -n "$fp" ]] && /usr/bin/ssh-add -l 2>/dev/null | grep -qF "$fp"; then
  echo "ключ подписи уже в агенте: $fp"
  exit 0
fi

# The passphrase comes from the Keychain, which is unlocked because a user agent starts
# after login.
/usr/bin/ssh-add --apple-use-keychain "$KEY"
/usr/bin/ssh-add -l
