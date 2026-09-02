# Put the terminal back into a plain state before every prompt.
#
# TUIs switch the terminal into reporting modes — mouse position (1000/1002/
# 1003/1006) and window focus (1004) — and are supposed to switch them off on
# the way out. Most do, on the paths their authors tested. A crash, a signal, a
# connection dropped mid-session, or an early exit down a diagnostic path leaves
# the terminal reporting to nobody, and from then on every click and every
# switch between windows arrives at the prompt as text: [I, [O, [<35;107;14M.
# The shell has no idea what those are, so they simply pile up on the line.
#
# Which program left it on is not worth chasing one at a time — atuin, fzf, an
# editor, a container TUI over a connection that dropped, they all can. The
# shell is the one place that sees the terminal between every pair of commands,
# and the fix costs a handful of bytes written to it.
#
# NOTE: precmd, so this runs BETWEEN commands and never while a TUI is up: a
# full-screen program legitimately keeps these modes on for as long as it runs.
# NOTE: harmless when nothing was left on — turning off a mode that is already
# off is defined and silent.
_term_reports_off() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l'
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _term_reports_off
