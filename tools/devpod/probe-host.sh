#!/bin/sh
# What one docker host knows about its devpod containers, in one round trip:
#   <workspace uid> <TAB> <state> <TAB> <image> <TAB> <secrets>
#
# `secrets` is three digits — claude, age, work env — or "--" when the
# container is not running and cannot be asked. 101 = token and env present,
# age key missing.
#
# Runs on the provider host: locally as `sh probe-host.sh`, remotely as
# `ssh host sh -s < probe-host.sh`. A FILE and not an inline command string
# because the inner test needs its own quotes, and nesting them through zsh and
# then through ssh is where this kind of thing usually breaks.
#
# POSIX sh: the remote side is whatever the host has, not necessarily zsh.

TAB=$(printf '\t')

docker ps -a --filter label=dev.containers.id \
  --format "{{.ID}}${TAB}{{.Label \"dev.containers.id\"}}${TAB}{{.State}}${TAB}{{.Image}}" \
  2>/dev/null | while IFS="$TAB" read -r cid uid state image; do
    [ -n "$uid" ] || continue
    sec='---'
    if [ "$state" = running ]; then
      # One exec per container, not one per file: exec is the expensive part.
      # NOTE: every home, not just $HOME. `docker exec` runs as the image's
      # user, which is root on a container built from somebody else's
      # devcontainer.json — while the secrets went to the user you actually log
      # in as. Checking only $HOME reported everything missing on exactly those
      # workspaces, including immediately after a successful delivery.
      sec=$(docker exec "$cid" sh -c 'c=0; a=0; e=0
for h in /root /home/*; do
  [ -f "$h/.config/claude/token" ] && c=1
  [ -f "$h/.config/dp/work.env" ] && e=1
  [ -f "$h/.config/sops/age/keys.txt" ] && a=1
done
printf "%s%s%s" "$c" "$a" "$e"' 2>/dev/null)
      [ -n "$sec" ] || sec='???'
    fi
    printf '%s%s%s%s%s%s%s\n' "$uid" "$TAB" "$state" "$TAB" "$image" "$TAB" "$sec"
  done

# The sentinel is the whole point of this line: without it an empty answer is
# ambiguous — a host with no devpod containers looks exactly like a host that
# never answered, and the caller then reports every workspace on it as having
# lost its container. Which is what a dropped ssh connection used to look like.
echo '#ok'
