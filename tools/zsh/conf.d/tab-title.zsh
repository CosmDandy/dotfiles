# Renames the terminal tab OUTSIDE tmux; inside tmux pane-title.sh owns the title and this
# stays silent. The icon reflects the machine type: container, VM, or nothing on bare
# hardware.
# NOTE: ssh sessions are left alone — the local shell blocks while ssh runs and the remote
# side sets its own title.
# The tab name is the directory basename, with "· <cmd>" appended while a command runs.

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

_tabtitle_emit() { printf '\e]2;%s\a' "$1"; }

_tabtitle_set() {
    emulate -L zsh
    local extra="$1" name
    name="${${PWD/#$HOME/~}:t}"
    _tabtitle_emit "${_tabtitle_icon}${name}${extra:+ · $extra}"
}

_tabtitle_precmd()  { [[ -n "$TMUX" ]] && return; _tabtitle_set }
_tabtitle_preexec() { [[ -n "$TMUX" ]] && return; _tabtitle_set "${1%% *}" }

autoload -Uz add-zsh-hook
add-zsh-hook precmd  _tabtitle_precmd
add-zsh-hook preexec _tabtitle_preexec
