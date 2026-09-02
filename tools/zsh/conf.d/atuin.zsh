# Keep zsh-autosuggestions away from atuin's widgets.
#
# The plugin wraps every widget that exists when it starts, and its wrapper
# restores the line around the call — so the command atuin puts there through
# LBUFFER is thrown away. From the outside the key looks dead: the search opens,
# a command is chosen, and nothing arrives on the prompt.
#
# Containers are where this bites. There atuin registers before the plugin
# starts and its widgets get wrapped; on the mac the deferred load happens to
# put atuin last, so nothing wraps it. That is a coincidence of ordering rather
# than a rule — which is the whole reason this file exists. Anything that moves
# the queue (turbo mode, one more plugin, a reordered defer) would silently
# bring the dead key back.
#
# NOTE: the whole list, not an append. The plugin fills IGNORE_WIDGETS with its
# own defaults ONLY when the variable is unset, so declaring just atuin-* here
# would quietly drop the eight entries it ships with. Copied verbatim from
# zsh-autosuggestions.zsh — the globs are escaped there and must stay escaped.
# NOTE: no _atuin_* entry. The plugin already skips every widget starting with
# an underscore, unconditionally.
typeset -ga ZSH_AUTOSUGGEST_IGNORE_WIDGETS
ZSH_AUTOSUGGEST_IGNORE_WIDGETS=(
  orig-\*
  beep
  run-help
  set-local-history
  which-command
  yank
  yank-pop
  zle-\*
  atuin-\*
)

# Take the chosen command off stderr instead of stdout.
#
# atuin falls back to full screen whenever its stdout is not a terminal, and then
# ignores inline_height, inline_height_shell_up_key_binding and even an explicit
# --inline-height. The stock widget captures the choice through $(...) with
# 3>&1 1>&2 2>&3 — both halves of that are enough to trigger it on their own,
# measured. So read the result off stderr, the same channel atuin's own
# tmux-popup branch uses, and leave stdout on the terminal. Everything else
# mirrors the stock _atuin_search.
#
# In a container the stock widget does not merely lose the inline height: it
# comes back with nothing at all (status 0, empty output, measured), so the key
# looks dead. That is why this lives in conf.d rather than in .zshrc — conf.d is
# read from the clone and arrives with a `git pull`, while .zshrc is a symlink
# into the image's nix store and only changes when the image is rebuilt.
_atuin_inline_height() {
    (( $+functions[_atuin_search] )) || return 0
    typeset -g _ATUIN_INLINE_PATCHED=1
    _atuin_search() {
        emulate -L zsh
        zle -I
        local output ret file
        file=${TMPDIR:-/tmp}/atuin-result.$$
        ATUIN_SHELL=zsh ATUIN_QUERY=$BUFFER atuin search "$@" -i 2> "$file"
        ret=$?
        output=$(<"$file")
        command rm -f "$file"
        # NOTE: the result channel is not private. atuin writes diagnostics to
        # the same stderr — "database version migration" after an upgrade is the
        # one seen in the wild — and everything on that channel goes straight
        # into the command line. So take the LAST line (the result is printed
        # last) and refuse anything carrying an escape, which a command never
        # does and a stray terminal report always does.
        output=${output##*$'\n'}
        [[ $output == *$'\e'* ]] && output=
        # NOTE: atuin turns on mouse and focus reporting for its TUI and clears
        # them on the way out — but not on every path out. A crash, a signal, or
        # an early exit like that migration leaves the terminal reporting, and
        # every click and focus change then lands in the next prompt as [I, [O
        # and [<35;107;14M. Undoing it costs one write and is correct even when
        # nothing was left on.
        printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l' > /dev/tty
        zle reset-prompt
        echo -n ${zle_bracketed_paste[1]} > /dev/tty
        if (( ret != 0 )); then
            [[ -n $output ]] && print -r -- "$output" > /dev/tty
            return $ret
        fi
        [[ -n $output ]] || return 0
        RBUFFER=""
        LBUFFER=${output#__atuin_accept__:}
        [[ $output == __atuin_accept__:* ]] && zle accept-line
    }
}

# The safety net for a shell whose .zshrc does not know to call the above —
# every container until its image is rebuilt. It cannot be applied here and now:
# conf.d is sourced hundreds of lines before atuin initialises, so there is no
# widget to replace yet. So wait for one, patch it once, and get out of the way.
autoload -Uz add-zsh-hook
_atuin_widget_patch() {
    (( _ATUIN_INLINE_PATCHED )) && { add-zsh-hook -d precmd _atuin_widget_patch; return 0 }
    (( $+functions[_atuin_search] )) || return 0
    _atuin_inline_height
    add-zsh-hook -d precmd _atuin_widget_patch
}
add-zsh-hook precmd _atuin_widget_patch
