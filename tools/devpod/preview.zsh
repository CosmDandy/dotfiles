#!/usr/bin/env zsh

# Detail pane for the devpod picker: one workspace, read out of the snapshot
# that conf.d/devpod.zsh prepared before opening fzf.
#
# A standalone script and not a shell function on purpose — fzf runs --preview
# through its own process, where the interactive shell's functions do not exist.
#
# Usage: preview.zsh <id> <snapshot>

emulate -L zsh
setopt local_options

local id=$1 snap=$2
[[ -n $id && -r $snap ]] || { print -r -- "no data"; exit 0 }

local M=$'\e[38;2;88;110;117m' G=$'\e[38;2;133;153;0m' Y=$'\e[38;2;181;137;0m' \
      B=$'\e[38;2;38;139;210m' O=$'\e[0m'

local line
line=$(awk -F'\t' -v i="$id" '$1==i{print; exit}' "$snap")
[[ -n $line ]] || { print -r -- "no data for $id"; exit 0 }

local -a c=(${(ps:\t:)line})
local state=$c[2] prov=$c[3] host=$c[4] uid=$c[5] image=$c[6] date=$c[7] \
      src=$c[8] profile=$c[9] secrets=$c[11]

local state_word
case $state in
  running) state_word="${G}running${O}" ;;
  exited)  state_word="${B}stopped${O}" ;;
  new)     state_word="${M}not created${O}" ;;
  # NOTE: told apart on purpose. "gone" means the host answered and the
  # container is not there; "silent" means nobody answered, which is a network
  # problem and not a reason to recreate anything.
  unknown) state_word="${Y}host did not answer — state unknown${O}" ;;
  *)       state_word="${Y}workspace exists, container gone${O}" ;;
esac

# NOTE: an instance made by `dp new` has no catalog line, so the profile is
# unknown there — but the image tag is the profile, so read it back rather than
# printing a dash next to a perfectly informative image name.
[[ $profile == - && $image == *:* ]] && profile="${image##*:} (from image)"

print -r -- "${M}repository ${O}  ${src:--}"
print -r -- "${M}profile    ${O}  ${profile:--}"
print -r -- "${M}state      ${O}  $state_word"
[[ $state != new ]] && {
  [[ $host == - ]] && host=
  print -r -- "${M}provider   ${O}  ${prov}${host:+   ${M}host${O} $host}"
  print -r -- "${M}last used  ${O}  ${date}"
  print -r -- "${M}image      ${O}  ${image:--}"
}
print -r -- ""

# The one check that costs nothing and has already bitten: a workspace pinned to
# our registry tag but running something else means the override was lost and
# the repository's own devcontainer.json won.
setopt local_options extended_glob
case $image in
  ghcr.io/cosmdandy/devcontainer:*) print -r -- "${G}✓${O} image from the registry" ;;
  vsc-*|*devpod-*)                  print -r -- "${Y}⚠${O} image built locally, not from the registry" ;;
  -|'')                             : ;;
  # a bare 12-hex id is what docker reports when the tag it was built from is gone
  [0-9a-f](#c12))                   print -r -- "${Y}⚠${O} untagged image (${image}) — the registry has moved on" ;;
  *)                                print -r -- "${Y}⚠${O} foreign image, not from our registry" ;;
esac

# NOTE: anything inside the container (secrets, git state) needs it running, so
# say so rather than showing a blank where a check should be.
# Secrets are the one piece of container state that goes missing on its own:
# they live in the container's home and a recreate takes them with it. So they
# get a line of their own rather than a pointer to the doctor.
if [[ $state == running ]]; then
  local cl=${secrets[1]} ag=${secrets[2]} ev=${secrets[3]} mark
  [[ $cl == 1 ]] && mark="${G}✓${O} Claude token" || mark="${Y}✗${O} Claude token"
  [[ $ag == 1 ]] && mark="$mark   ${G}✓${O} age key" || mark="$mark   ${Y}✗${O} age key"
  [[ $ev == 1 ]] && mark="$mark   ${G}✓${O} work env" || mark="$mark   ${Y}✗${O} work env"
  print -r -- "$mark"
  [[ $cl == 1 && $ag == 1 && $ev == 1 ]] || \
    print -r -- "${M}restore: dp secrets $id (Ctrl-S)${O}"
  print -r -- "${M}git state — dp doctor $id${O}"
elif [[ $state != new ]]; then
  print -r -- "${M}container not running — nothing to check secrets or git against${O}"
fi
