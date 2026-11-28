#!/usr/bin/env zsh
set -eu
source "${0:A:h:h}/zsh/conf.d/devpod.zsh"

_dp_ws_field() { return 0; }
_dp_log() { return 0; }
_dp_secrets() { return 0; }
_dp_recreate_preflight() { [[ $1 != blocked ]] || return 2; }
devpod() {
  [[ $1 == up && $3 == --recreate ]] || return 99
  print -r -- "up:$2"
  [[ $2 != failed ]]
}

output=$(dp recreate blocked allowed) && exit 1 || rc=$?
[[ $rc == 2 && $output != *up:blocked* && $output == *up:allowed* ]]
output=$(dp recreate blocked failed allowed) && exit 1 || rc=$?
[[ $rc == 1 && $output == *up:failed* && $output == *up:allowed* ]]

unfunction _dp_recreate_preflight
output=$(dp recreate legacy)
[[ $output == *up:legacy* ]]
print 'PASS: recreate preflight, batch status, and optional hook'
