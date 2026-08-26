# Detects the terminal background with an OSC 11 query — the shared helper behind the k9s
# and lazygit wrappers. Works on the mac and in a container; inside tmux (>= 3.3) tmux
# forwards the query to the pane.
# NOTE: passthrough must NOT be used here, or tmux never returns the answer.
# Exit code: 0 light, 1 dark, 2 the terminal did not answer. Debug with TERM_BG_DEBUG=1.
_term_is_light() {
    _TERM_BG_LAST_RESP=""
    [[ -t 1 ]] || { [[ -n "$TERM_BG_DEBUG" ]] && print -u2 "term-bg: stdout не tty"; return 2; }
    local q=$'\e]11;?\e\\'
    local old c resp=""
    old=$(stty -g 2>/dev/null) || { [[ -n "$TERM_BG_DEBUG" ]] && print -u2 "term-bg: stty недоступен"; return 2; }
    stty -echo 2>/dev/null
    printf '%s' "$q" > /dev/tty
    local to=0.6
    while IFS= read -rs -t $to -k 1 c < /dev/tty; do
        to=0.2
        resp+="$c"
        [[ "$c" == $'\a' || "$c" == '\' ]] && break
    done
    stty "$old" 2>/dev/null
    _TERM_BG_LAST_RESP="$resp"
    [[ -n "$TERM_BG_DEBUG" ]] && print -u2 "term-bg: TMUX=${TMUX:+yes} raw=[${(V)resp}]"
    [[ "$resp" == *rgb:* ]] || return 2
    local hex="${resp##*rgb:}" f1 f2 f3
    f1="${hex%%/*}"; hex="${hex#*/}"
    f2="${hex%%/*}"; hex="${hex#*/}"
    f3="${hex%%[!0-9a-fA-F]*}"
    local r=$((16#${f1:0:2})) g=$((16#${f2:0:2})) b=$((16#${f3:0:2}))
    local lum=$(( (r*299 + g*587 + b*114)/1000 ))
    [[ -n "$TERM_BG_DEBUG" ]] && print -u2 "term-bg: rgb lum=$lum -> $(( lum > 128 ? 1 : 0 )) (1=light)"
    (( lum > 128 ))
}
