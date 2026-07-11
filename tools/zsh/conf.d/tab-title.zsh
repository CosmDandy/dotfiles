# Автопереименование вкладки терминала БЕЗ tmux (в tmux рулит pane-title.sh — там молчим).
# Отражает ТИП машины, на которой запущен этот шелл:
#   контейнер -> 󰆦 , виртуалка -> 󰒋 , Mac/железо -> без иконки.
# SSH не трогаем: уходя по ssh, локальный шелл блокируется, удалёнка сама ставит свой заголовок.
# Имя вкладки = басенейм каталога; во время команды дописывает "| <cmd>".

_tabtitle_in_container() {
    [[ "$OSTYPE" == linux* ]] || return 1
    [[ -e /run/.containerenv || -e /.dockerenv || -e /run/host/container-manager ]] && return 0
    if [[ -r /run/systemd/container ]]; then
        local c; read -r c < /run/systemd/container
        [[ "$c" != wsl ]] && return 0
    fi
    return 1
}

# Иконку машины считаем один раз при загрузке — тип машины за сессию не меняется.
_tabtitle_icon=''
if _tabtitle_in_container; then
    _tabtitle_icon='󰆦 '
elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q -v; then
    _tabtitle_icon='󰒋 '
fi

_tabtitle_emit() { printf '\e]2;%s\a' "$1"; }

_tabtitle_set() {
    emulate -L zsh
    local extra="$1" name
    name="${${PWD/#$HOME/~}:t}"
    _tabtitle_emit "${_tabtitle_icon}${name}${extra:+ | $extra}"
}

_tabtitle_precmd()  { [[ -n "$TMUX" ]] && return; _tabtitle_set }
_tabtitle_preexec() { [[ -n "$TMUX" ]] && return; _tabtitle_set "${1%% *}" }

autoload -Uz add-zsh-hook
add-zsh-hook precmd  _tabtitle_precmd
add-zsh-hook preexec _tabtitle_preexec
