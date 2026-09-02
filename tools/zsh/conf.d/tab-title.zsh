# Renames the terminal tab OUTSIDE tmux; inside tmux pane-title.sh owns the title and this
# stays silent. The icon reflects the machine type: container, VM, or nothing on bare
# hardware.
# The tab name is the directory basename, with "· <cmd>" appended while a command runs.
# NOTE: ssh is named by its target host instead. Most hosts overwrite that on their first
# prompt — a stock Debian .bashrc emits OSC 0 with user@host — but Proxmox never does:
# /root/.bashrc there is the fully commented-out root template, so nothing overwrote what
# preexec had left and the title kept showing the local directory for the whole session.

_tabtitle_in_container() {
    [[ "$OSTYPE" == linux* ]] || return 1
    [[ -e /run/.containerenv || -e /.dockerenv || -e /run/host/container-manager || -d /opt/orbstack-guest ]] && return 0
    if [[ -r /run/systemd/container ]]; then
        local c; read -r c < /run/systemd/container
        [[ "$c" != wsl ]] && return 0
    fi
    return 1
}

# the machine type cannot change within a session, so it is computed once at load
_tabtitle_icon=''
if _tabtitle_in_container; then
    _tabtitle_icon='󰆧 '
elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q -v; then
    _tabtitle_icon='󰒋 '
fi

_tabtitle_emit() { printf '\e]2;%s\a' "$1" }

_tabtitle_set() {
    emulate -L zsh
    local extra="$1" name
    name="${${PWD/#$HOME/~}:t}"
    _tabtitle_emit "${_tabtitle_icon}${name}${extra:+ · $extra}"
}

# The first non-option word of an ssh command line, minus any user@ prefix. The bracket
# class is every short option that takes a separate argument; its value must not be
# mistaken for the host.
_tabtitle_ssh_host() {
    emulate -L zsh
    local -a words=(${(z)1})
    local w skip=0
    shift words
    for w in $words; do
        if (( skip )); then
            skip=0
        elif [[ $w == -[bcDEeFIiJLlmOopQRSWw] ]]; then
            skip=1
        elif [[ $w != -* ]]; then
            print -r -- "${w#*@}"
            return 0
        fi
    done
    return 1
}

_tabtitle_precmd()  { [[ -n "$TMUX" ]] && return; _tabtitle_set }
_tabtitle_preexec() {
    [[ -n "$TMUX" ]] && return
    local cmd="${1%% *}"
    if [[ $cmd == ssh ]]; then
        local host="$(_tabtitle_ssh_host "$1")"
        [[ -n "$host" ]] && { _tabtitle_emit "󰒋 $host"; return }
    fi
    _tabtitle_set "$cmd"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd  _tabtitle_precmd
add-zsh-hook preexec _tabtitle_preexec
