#!/usr/bin/env zsh

# The picker's footer, rebuilt whenever the tmux flag changes.
#
# A script rather than a string in the caller for two reasons: fzf's
# transform-footer runs a COMMAND and takes its output, which is what lets the
# flag show its state in colour; and the footer has to fit, which depends on how
# wide the picker is at this moment.
#
# Width: fzf exports FZF_COLUMNS for the WHOLE window, while the footer lives in
# the list half — the preview takes 46% — so the room here is roughly half of
# that. Past that width the line was silently cut mid-word, which is how "tmux"
# turned into a dangling colon on screen.
#
# Two shapes. Without a second argument it describes the full picker; with
# "simple" it describes the plain chooser `ds` opens, where the only actions are
# picking a row and the tmux flag.
#
# Usage: footer.zsh <flag-file> [simple]

emulate -L zsh

local flag=$1
local mode=off
[[ -r $flag ]] && mode=$(< $flag)

local B=$'\e[38;2;38;139;210m' G=$'\e[38;2;133;153;0m' R=$'\e[38;2;220;50;47m' \
      M=$'\e[38;2;88;110;117m' F=$'\e[2m' O=$'\e[0m'
local a="${F}${M}"

# The flag carries its state in colour, so the word never has to say "off".
local tmux_word=tmux tmux_short=tmux tmux_colour=$R
case $mode in
  on)   tmux_colour=$G ;;
  # The short form keeps a single "+": on and exit are both green, and without
  # it the two on-states are indistinguishable in a narrow window.
  exit) tmux_colour=$G; tmux_word='tmux+close'; tmux_short='tmux+' ;;
esac

local -i cols=${FZF_COLUMNS:-${COLUMNS:-120}}
# 54% for the list, minus the border and the padding fzf puts around it.
local -i room=$(( cols * 54 / 100 - 4 ))

# Four progressively shorter forms, and the one that actually FITS wins —
# measured, not guessed from a width threshold. The flag's own label changes
# length ("tmux" vs "tmux+close"), and picking the tier by width alone cut the
# last word in half exactly when the flag was on.
if [[ $2 == simple ]]; then
  local -a sk=(Enter ⇥ ^T) sl=(open mark "$tmux_word")
  local -i sn=0 si
  for (( si = 1; si <= $#sk; si++ )); do
    (( sn += ${#sk[si]} + 1 + ${#sl[si]} ))
    (( si < $#sk )) && (( sn += 2 ))
  done
  (( sn > room )) && sl=(open mark "$tmux_short")
  local sout=
  for (( si = 1; si <= $#sk; si++ )); do
    local sc=$a
    (( si == $#sk )) && sc=$tmux_colour
    sout+="${B}${sk[si]}${O} ${sc}${sl[si]}${O}"
    (( si < $#sk )) && sout+='  '
  done
  print -rn -- "$sout"
  return 0
fi

local -a k_full=(Enter ^N ^S ^X ^R ^L ^D ^T)
local -a l_full=(open new secrets stop recreate log delete "$tmux_word")
local -a k_short=(↵ ^N ^S ^X ^R ^L ^D ^T)
local -a l_short=(open new keys stop rebuild log rm "$tmux_word")
local -a k_min=(↵ ^N ^S ^X ^R ^T)
# NOTE: the short label here, always. The difference between "tmux" and
# "tmux+close" is six characters, and paying for them by dropping every other
# word is a bad trade — the colour already says the flag is on, and the third
# state is visible in the wider forms and in `dp tmux`.
local -a l_min=(open new keys stop rebuild "$tmux_short")
# Nothing but the keys: at this width the preview is useless anyway and the
# person is here to press something, not to read.
local -a l_bare=('' '' '' '' '' '')

# Plain length of a form, ANSI excluded — that is what has to fit.
_fits() {
  local -a kk=("${(@P)1}") ll=("${(@P)2}")
  local -i n=0 j
  for (( j = 1; j <= $#kk; j++ )); do
    (( n += ${#kk[j]} ))
    [[ -n ${ll[j]} ]] && (( n += 1 + ${#ll[j]} ))
    (( j < $#kk )) && (( n += 2 ))
  done
  (( n <= room ))
}

local -a keys labels
if _fits k_full l_full;    then keys=($k_full);  labels=($l_full)
elif _fits k_short l_short; then keys=($k_short); labels=($l_short)
elif _fits k_min l_min;     then keys=($k_min);   labels=($l_min)
else                             keys=($k_min);   labels=($l_bare)
fi

local -i i
local out=
for (( i = 1; i <= $#keys; i++ )); do
  # The tmux entry is the only one that changes colour, and it is always last.
  local colour=$a
  (( i == $#keys )) && colour=$tmux_colour
  out+="${B}${keys[i]}${O}"
  [[ -n ${labels[i]} ]] && out+=" ${colour}${labels[i]}${O}"
  (( i < $#keys )) && out+='  '
done
print -rn -- "$out"
