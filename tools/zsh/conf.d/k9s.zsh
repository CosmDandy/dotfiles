# k9s: автопереключение Solarized dark/light под тему терминала.
# Базовый скин — Solarized Dark; для светлого фона добавляем --invert => Light.
# Фон определяем запросом OSC 11 у терминала (работает и на маке, и в контейнере).
# Возврат: 0 — светлый фон, 1 — тёмный, 2 — терминал не ответил.
_k9s_term_is_light() {
    _K9S_LAST_RESP=""
    [[ -t 1 ]] || { [[ -n "$K9S_DEBUG" ]] && print -u2 "k9s-debug: stdout не tty"; return 2; }
    # Обычный OSC 11: вне tmux идёт прямо в терминал; внутри tmux (>=3.3) tmux
    # сам форвардит запрос внешнему терминалу и роутит ответ в активную панель.
    # passthrough-обёртку НЕ используем — иначе tmux не вернёт ответ в панель.
    local q=$'\e]11;?\e\\'
    local old c resp=""
    old=$(stty -g 2>/dev/null) || { [[ -n "$K9S_DEBUG" ]] && print -u2 "k9s-debug: stty недоступен"; return 2; }
    stty -echo 2>/dev/null
    printf '%s' "$q" > /dev/tty
    # первый символ ждём дольше (форвардинг через tmux + сетевая задержка),
    # последующие — коротко, т.к. ответ приходит сплошным потоком
    local to=0.6
    while IFS= read -rs -t $to -k 1 c < /dev/tty; do
        to=0.2
        resp+="$c"
        [[ "$c" == $'\a' || "$c" == '\' ]] && break
    done
    stty "$old" 2>/dev/null
    _K9S_LAST_RESP="$resp"
    if [[ -n "$K9S_DEBUG" ]]; then
        print -u2 "k9s-debug: TMUX=${TMUX:+yes} сырой ответ=[${(V)resp}]"
    fi
    [[ "$resp" == *rgb:* ]] || return 2
    local hex="${resp##*rgb:}" f1 f2 f3
    f1="${hex%%/*}"; hex="${hex#*/}"
    f2="${hex%%/*}"; hex="${hex#*/}"
    f3="${hex%%[!0-9a-fA-F]*}"
    local r=$((16#${f1:0:2})) g=$((16#${f2:0:2})) b=$((16#${f3:0:2}))
    local lum=$(( (r*299 + g*587 + b*114)/1000 ))
    [[ -n "$K9S_DEBUG" ]] && print -u2 "k9s-debug: rgb=${f1:0:2}/${f2:0:2}/${f3:0:2} (r=$r g=$g b=$b) lum=$lum -> $(( lum > 128 ? 1 : 0 )) (1=light)"
    (( lum > 128 ))
}

k9s() {
    local invert
    case "$K9S_INVERT" in
        1|true|light) invert=1 ;;          # ручной override: светлая
        0|false|dark) invert=0 ;;          # ручной override: тёмная
        *)
            _k9s_term_is_light
            case $? in
                0) invert=1 ;;             # светлый фон терминала
                1) invert=0 ;;             # тёмный фон терминала
                *)                         # терминал не ответил — fallback на тему macOS
                    if [[ "$OSTYPE" == darwin* ]] && ! defaults read -g AppleInterfaceStyle &>/dev/null; then
                        invert=1
                    else
                        invert=0
                    fi ;;
            esac ;;
    esac
    if (( invert )); then
        command k9s --invert "$@"
    else
        command k9s "$@"
    fi
}
